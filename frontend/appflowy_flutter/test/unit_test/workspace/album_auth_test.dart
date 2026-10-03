import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/external_collection_host.dart';
import 'package:appflowy/plugins/collection/providers/external_repository_view.dart';
import 'package:appflowy/plugins/collection/providers/google_photos_keep.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/collection/views/album/album_host.dart';
import 'package:appflowy/plugins/collection/views/album/album_thumbnail.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/services/google_photos_provider.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _connection = ProviderConnection(
  id: 'google|album-widget-test',
  service: ProviderService.googlePhotos,
  accountLabel: 'Album test',
);

const _photo = ProviderNode(
  id: 'photo',
  name: 'Photo.jpg',
  kind: ProviderNodeKind.image,
  thumbnailUrl: 'https://example.test/thumbnail',
  downloadUrl: 'https://example.test/photo',
);

const _lapsed = ProviderFailure(
  ProviderStatus.notFound,
  detail: ProviderFailure.selectionLapsed,
);

void main() {
  late Directory cacheRoot;
  late CollectionSource source;
  late ProviderFailure? nextFailure;
  late List<ProviderNode> nextItems;
  final created = <_PhotoProvider>[];
  var selection = 0;

  setUpAll(() async {
    cacheRoot = await Directory.systemTemp.createTemp('appflowy-album-auth-');
    getIt.registerSingleton<ApplicationDataStorage>(
      _DataStorage(cacheRoot.path),
    );
    await ProviderConnections.instance.upsert(
      _connection,
      const ProviderCredentials(accessToken: 'test-only'),
    );
  });

  setUp(() async {
    source = CollectionSource(
      service: ProviderService.googlePhotos,
      connectionId: _connection.id,
      remoteId: 'selection-${selection++}',
    );
    nextFailure = const ProviderFailure.authExpired();
    nextItems = const [];
    created.clear();
    ProviderRegistry.register(ProviderService.googlePhotos, (_, source) {
      final provider = _PhotoProvider(source)
        ..failure = nextFailure
        ..items = nextItems;
      created.add(provider);
      return provider;
    });
    // Cache reads during a widget frame are in memory. All disk setup stays
    // outside the fake-async widget body and never touches the user's cache.
    await ProviderCache.instance.writeJson(source.cacheKey, 'root', const []);
  });

  tearDown(ProviderRegistry.reset);
  tearDownAll(() async {
    await ProviderConnections.instance.remove(_connection.id);
    await getIt.unregister<ApplicationDataStorage>();
    try {
      await cacheRoot.delete(recursive: true);
    } on FileSystemException catch (error) {
      // A background cache write may still be closing its handle on Windows.
      // This directory contains only disposable test data; don't turn that
      // cleanup lock into an authentication-test failure.
      if (!Platform.isWindows || error.osError?.errorCode != 32) {
        rethrow;
      }
    }
  });

  for (final appearance in [
    (name: 'light', brightness: Brightness.light, paper: false),
    (name: 'dark', brightness: Brightness.dark, paper: false),
    (name: 'paper', brightness: Brightness.light, paper: true),
  ]) {
    for (final definition
        in CollectionRegistry.typeFor(CollectionKind.album).views) {
      testWidgets('${definition.id} offers sign in in ${appearance.name} mode',
          (tester) async {
        CollectionSource? requested;
        final collection = _collection(source, definition);
        try {
          await tester.pumpWidget(
            _app(
              onReconnect: (value) => requested = value,
              brightness: appearance.brightness,
              paper: appearance.paper,
              child: Builder(
                builder: (context) => definition.builder(context, collection),
              ),
            ),
          );
          await tester.pump();

          expect(find.byType(CircularProgressIndicator), findsNothing);
          final state = tester.widget<ProviderStateView>(
            find.byType(ProviderStateView),
          );
          expect(state.status, ProviderStatus.authExpired);
          expect(state.onReconnect, isNotNull);
          expect(find.text(LocaleKeys.providers_tryAgain), findsNothing);
          if (appearance.paper) {
            expect(state.palette.surface, PaperTheme.editorPreviewBackground);
          }

          await tester.tap(find.text(LocaleKeys.providers_reconnect));
          expect(requested?.connectionId, _connection.id);
          expect(requested?.cacheKey, source.cacheKey);

          await tester.pump(const Duration(minutes: 30));
          expect(created.single.listCalls, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }

  testWidgets('cached items keep a reconnect banner and stop spinning',
      (tester) async {
    await tester.runAsync(
      () => ProviderCache.instance.writeJson(
        source.cacheKey,
        'root',
        [_photo.toJson()],
      ),
    );
    final collection = _collection(source);
    AlbumController? album;
    try {
      await tester.pumpWidget(
        _app(
          onReconnect: (_) {},
          child: AlbumHost(
            collection: collection,
            builder: (context, controller, palette) {
              album = controller;
              return Column(
                children: [
                  Text('Items: ${controller.items.length}'),
                  for (final item in controller.items)
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: AlbumThumbnail(item: item, palette: palette),
                    ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ProviderStaleBanner), findsOneWidget);
      expect(find.text(LocaleKeys.providers_reconnect), findsOneWidget);
      expect(find.text('Items: 1'), findsOneWidget);
      expect(album!.items.single.id, '${collection.collectionView.id}::photo');
      expect(album!.items.single.unavailable, isTrue);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  });

  for (final listView in [false, true]) {
    testWidgets('${listView ? 'list' : 'album'} resumes after signing in',
        (tester) async {
      final collection = _collection(source);
      final body = listView
          ? ExternalCollectionHost(
              collection: collection,
              builder: (_, __, ___) => const Text('Album ready'),
            )
          : AlbumHost(
              collection: collection,
              builder: (_, __, ___) => const Text('Album ready'),
            );
      try {
        await tester.pumpWidget(
          _app(onReconnect: (_) {}, child: body),
        );
        await tester.pump();
        expect(find.text(LocaleKeys.providers_reconnect), findsOneWidget);
        expect(created, hasLength(1));

        // Same account and same source, just fresh credentials: neither
        // switching views nor reselecting the Google Photos album is needed.
        nextFailure = null;
        // Credentials use the in-memory/null KV store here. Keep the
        // notification and the refresh it starts on Flutter's test clock.
        await ProviderConnections.instance.updateCredentials(
          _connection.id,
          const ProviderCredentials(accessToken: 'renewed-test-only'),
        );
        await tester.pump();

        expect(created, hasLength(2));
        expect(created.first.disposed, isTrue);
        expect(created.last.listCalls, 1);
        expect(find.text('Album ready'), findsOneWidget);
        expect(find.text(LocaleKeys.providers_reconnect), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
    });
  }

  for (final (name, cached, listView) in [
    ('album', false, false),
    ('album over cached photos', true, false),
    ('list', false, true),
    ('list over cached photos', true, true),
  ]) {
    testWidgets('a lapsed selection offers to choose again: $name',
        (tester) async {
      nextFailure = _lapsed;
      if (cached) {
        await tester.runAsync(
          () => ProviderCache.instance.writeJson(
            source.cacheKey,
            'root',
            [_photo.toJson()],
          ),
        );
      }
      final collection = _collection(source);
      try {
        await tester.pumpWidget(
          _app(
            onReconnect: (_) {},
            onSourceChanged: (_) {},
            child: listView
                ? ExternalCollectionHost(
                    collection: collection,
                    builder: (_, __, ___) => const Text('Album ready'),
                  )
                : AlbumHost(
                    collection: collection,
                    builder: (_, __, ___) => const Text('Album ready'),
                  ),
          ),
        );
        await tester.pump();

        expect(
          find.text(LocaleKeys.providers_photos_chooseAgain),
          findsOneWidget,
        );
        // Neither of these can bring a lapsed selection back.
        expect(find.text(LocaleKeys.providers_tryAgain), findsNothing);
        expect(find.text(LocaleKeys.providers_reconnect), findsNothing);
        if (cached) {
          expect(find.byType(ProviderStaleBanner), findsOneWidget);
          expect(
            find.text(LocaleKeys.providers_photos_lapsedBody),
            findsOneWidget,
          );
        } else {
          expect(
            find.text(LocaleKeys.providers_photos_expiredTitle),
            findsOneWidget,
          );
        }
        expect(find.byIcon(Icons.timer_off_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
    });
  }

  for (final canRebind in [null, false]) {
    testWidgets(
        'a lapsed selection is not re-picked '
        '${canRebind == null ? 'outside a collection page' : 'on a page that may not change'}',
        (tester) async {
      nextFailure = _lapsed;
      try {
        await tester.pumpWidget(
          _app(
            onReconnect: (_) {},
            onSourceChanged: canRebind == null ? null : (_) {},
            canRebind: canRebind ?? true,
            child: AlbumHost(
              collection: _collection(source),
              builder: (_, __, ___) => const Text('Album ready'),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text(LocaleKeys.providers_photos_chooseAgain),
          findsNothing,
        );
        expect(
          find.text(LocaleKeys.providers_state_missingTitle),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
    });
  }

  testWidgets('choosing again asks, then keeps or links the new selection',
      (tester) async {
    final persisted = <CollectionSource>[];
    final pickedFor = <ProviderConnection>[];
    final kept = <(String, CollectionSource)>[];
    final explorer = _Explorer();
    final collection = _collectionWith(source, explorer: explorer);
    CollectionSource? nextPick;
    bool? choice;
    var asked = 0;
    VoidCallback? Function(ProviderFailure?)? actionFor;
    try {
      await tester.pumpWidget(
        _app(
          onReconnect: (_) {},
          onSourceChanged: persisted.add,
          child: Builder(
            builder: (context) {
              actionFor = (failure) => pickPhotosAgainAction(
                    context,
                    collection: collection,
                    failure: failure,
                    pick: (context, {required connection}) async {
                      pickedFor.add(connection);
                      return nextPick;
                    },
                    ask: (context) {
                      asked++;
                      return Future.value(choice);
                    },
                    keep: (context, {required parentViewId, required picked}) {
                      kept.add((parentViewId, picked));
                      return Future.value(3);
                    },
                  );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Only a lapsed selection is re-picked.
      expect(actionFor!(null), isNull);
      expect(actionFor!(const ProviderFailure.authExpired()), isNull);
      expect(actionFor!(const ProviderFailure.notFound()), isNull);

      // Closing the picker without choosing changes nothing.
      actionFor!(_lapsed)!();
      await tester.pump();
      expect(pickedFor.single.id, _connection.id);
      expect(asked, 0);
      expect(persisted, isEmpty);

      nextPick = _picked('fresh-session');
      // Dismissing the question changes nothing either.
      actionFor!(_lapsed)!();
      await tester.pump();
      expect(asked, 1);
      expect(kept, isEmpty);
      expect(persisted, isEmpty);

      choice = false;
      actionFor!(_lapsed)!();
      await tester.pump();
      // Only linked: bound to the new selection, nothing copied.
      expect(kept, isEmpty);
      final linked = persisted.single;
      expect(linked.service, ProviderService.googlePhotos);
      expect(linked.remoteId, 'fresh-session');
      expect(
        linked.option<String>(GooglePhotosProvider.sessionOption),
        'fresh-session',
      );
      expect(linked.option<bool>(GooglePhotosProvider.linkOnlyOption), isTrue);
      expect(linked.cacheKey, isNot(source.cacheKey));

      choice = true;
      actionFor!(_lapsed)!();
      await tester.pump();
      expect(kept.single.$1, collection.collectionView.id);
      expect(kept.single.$2.remoteId, 'fresh-session');
      // Kept: the album reads its own copies from now on.
      expect(persisted.last.isLocal, isTrue);
      expect(explorer.refreshes, 1);
      expect(pickedFor, hasLength(4));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  });

  testWidgets('an album that only links picks again without asking',
      (tester) async {
    final linkOnly =
        source.withOption(GooglePhotosProvider.linkOnlyOption, true);
    final persisted = <CollectionSource>[];
    var asked = 0;
    var kept = 0;
    VoidCallback? action;
    try {
      await tester.pumpWidget(
        _app(
          onReconnect: (_) {},
          onSourceChanged: persisted.add,
          child: Builder(
            builder: (context) {
              action = pickPhotosAgainAction(
                context,
                collection: _collectionWith(linkOnly),
                failure: _lapsed,
                pick: (context, {required connection}) async =>
                    _picked('next-session'),
                ask: (context) {
                  asked++;
                  return Future.value(true);
                },
                keep: (context, {required parentViewId, required picked}) {
                  kept++;
                  return Future.value(1);
                },
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      action!();
      await tester.pump();

      expect(asked, 0);
      expect(kept, 0);
      final linked = persisted.single;
      expect(linked.remoteId, 'next-session');
      expect(linked.option<bool>(GooglePhotosProvider.linkOnlyOption), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  });

  for (final appearance in [
    (name: 'light', brightness: Brightness.light, paper: false),
    (name: 'dark', brightness: Brightness.dark, paper: false),
    (name: 'paper', brightness: Brightness.light, paper: true),
  ]) {
    testWidgets('the keep question answers each way in ${appearance.name} mode',
        (tester) async {
      final answers = <bool?>[];
      await tester.pumpWidget(
        _app(
          onReconnect: (_) {},
          brightness: appearance.brightness,
          paper: appearance.paper,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  answers.add(await askToKeepPhotos(context)),
              child: const Text('Ask'),
            ),
          ),
        ),
      );

      for (final (key, answer) in [
        ('keep-photos-copy', true),
        ('keep-photos-link', false),
        (null, null),
      ]) {
        await tester.tap(find.text('Ask'));
        await tester.pumpAndSettle();
        expect(
          find.text(LocaleKeys.providers_photos_keepTitle),
          findsOneWidget,
        );
        expect(find.text(LocaleKeys.providers_photos_keepCopy), findsOneWidget);
        expect(find.text(LocaleKeys.providers_photos_linkOnly), findsOneWidget);
        if (appearance.paper) {
          expect(
            tester.widget<ViewerCard>(find.byType(ViewerCard)).color,
            PaperTheme.popupBackground,
          );
        }
        await tester.tap(
          key == null
              ? find.text(LocaleKeys.button_cancel)
              : find.byKey(ValueKey(key)),
        );
        await tester.pumpAndSettle();
        expect(answers.last, answer);
      }
      expect(answers, [true, false, null]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, listView) in [('album', false), ('list', true)]) {
    testWidgets('a live selection offers to keep its photos: $name',
        (tester) async {
      nextFailure = null;
      nextItems = const [_photo];
      final collection = _collection(source);
      try {
        await tester.pumpWidget(
          _app(
            onReconnect: (_) {},
            onSourceChanged: (_) {},
            child: listView
                ? ExternalCollectionHost(
                    collection: collection,
                    builder: (_, __, ___) => const Text('Album ready'),
                  )
                : AlbumHost(
                    collection: collection,
                    builder: (_, __, ___) => const Text('Album ready'),
                  ),
          ),
        );
        await tester.pump();

        expect(find.text('Album ready'), findsOneWidget);
        expect(find.byType(ProviderKeepBanner), findsOneWidget);
        expect(find.text(LocaleKeys.providers_photos_keep), findsOneWidget);
        expect(find.text(LocaleKeys.providers_photos_linkOnly), findsOneWidget);
        expect(find.byType(ProviderStaleBanner), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
    });
  }

  for (final (name, linkOnly, canRebind) in [
    ('on a page that may not change', false, false),
    ('once somebody chose to only link', true, true),
  ]) {
    testWidgets('no keep offer $name', (tester) async {
      nextFailure = null;
      nextItems = const [_photo];
      final bound = linkOnly
          ? source.withOption(GooglePhotosProvider.linkOnlyOption, true)
          : source;
      try {
        await tester.pumpWidget(
          _app(
            onReconnect: (_) {},
            onSourceChanged: (_) {},
            canRebind: canRebind,
            child: AlbumHost(
              collection: _collection(bound),
              builder: (_, __, ___) => const Text('Album ready'),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Album ready'), findsOneWidget);
        expect(find.byType(ProviderKeepBanner), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
    });
  }

  testWidgets('a live selection is kept, or only linked, from its offer',
      (tester) async {
    nextFailure = null;
    nextItems = const [_photo];
    final persisted = <CollectionSource>[];
    final kept = <(String, CollectionSource)>[];
    final explorer = _Explorer();
    final collection = _collectionWith(source, explorer: explorer);
    final live = ProviderController(
      collectionId: collection.collectionView.id,
      source: source,
    );
    ({VoidCallback keep, VoidCallback linkOnly})? Function(ProviderController)?
        offerFor;
    try {
      unawaited(live.load());
      await tester.pumpWidget(
        _app(
          onReconnect: (_) {},
          onSourceChanged: persisted.add,
          child: Builder(
            builder: (context) {
              offerFor = (live) => keepPhotosOffer(
                    context,
                    collection: collection,
                    live: live,
                    keep: (context, {required parentViewId, required picked}) {
                      kept.add((parentViewId, picked));
                      return Future.value(1);
                    },
                  );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      expect(live.nodes.single.id, _photo.id);
      offerFor!(live)!.linkOnly();
      // Same selection, now marked as only linked.
      final linked = persisted.single;
      expect(linked.cacheKey, source.cacheKey);
      expect(linked.option<bool>(GooglePhotosProvider.linkOnlyOption), isTrue);
      expect(kept, isEmpty);

      offerFor!(live)!.keep();
      await tester.pump();

      // The selection it already has is kept; nothing is picked again.
      expect(kept.single.$1, collection.collectionView.id);
      expect(kept.single.$2.cacheKey, source.cacheKey);
      expect(persisted.last.isLocal, isTrue);
      expect(explorer.refreshes, 1);
      expect(tester.takeException(), isNull);
    } finally {
      live.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  });

  testWidgets('an album that keeps its photos shows its own files',
      (tester) async {
    await tester.runAsync(
      () => ProviderCache.instance.writeJson(
        source.cacheKey,
        'root',
        [_photo.toJson()],
      ),
    );
    final explorer = _Explorer();
    Widget album(CollectionSource bound) => _app(
          onReconnect: (_) {},
          child: AlbumHost(
            collection: _collectionWith(bound, explorer: explorer),
            builder: (context, controller, palette) =>
                Text('Items: ${controller.items.length}'),
          ),
        );
    try {
      await tester.pumpWidget(album(source));
      await tester.pump();
      expect(find.text('Items: 1'), findsOneWidget);
      expect(explorer.listeners, isEmpty);

      await tester.pumpWidget(album(CollectionSource.local));
      await tester.pump();

      // The service's picture is gone; the album now follows its own files.
      expect(find.text('Items: 0'), findsOneWidget);
      expect(explorer.listeners, hasLength(1));
      expect(explorer.loaded, ['album-auth-test']);
      expect(created.single.disposed, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(explorer.listeners, isEmpty);
  });
}

CollectionViewContext _collection(
  CollectionSource source, [
  CollectionViewDefinition? definition,
]) =>
    _collectionWith(source, definition: definition);

/// What Google's picker hands back for a fresh selection.
CollectionSource _picked(String session) => CollectionSource(
      service: ProviderService.googlePhotos,
      connectionId: _connection.id,
      remoteId: session,
      readOnly: true,
      options: {GooglePhotosProvider.sessionOption: session},
    );

CollectionViewContext _collectionWith(
  CollectionSource source, {
  CollectionViewDefinition? definition,
  WorkspaceExplorerController? explorer,
}) =>
    CollectionViewContext(
      collectionView: ViewPB(
        id: 'album-auth-test',
        name: 'Album',
        layout: ViewLayoutPB.Document,
        extra: source.mergeIntoExtra(''),
      ),
      metadata: const CollectionMetadata(kind: CollectionKind.album),
      definition: definition ??
          CollectionRegistry.typeFor(CollectionKind.album).defaultView,
      explorer: explorer ?? _Explorer(),
      onOpen: (_) {},
      onOpenView: (_) {},
      onStateChanged: (_, __) {},
    );

Widget _app({
  required ValueChanged<CollectionSource> onReconnect,
  required Widget child,
  ValueChanged<CollectionSource>? onSourceChanged,
  bool canRebind = true,
  Brightness brightness = Brightness.light,
  bool paper = false,
}) =>
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: [PaperThemeExtension(enabled: paper)],
      ),
      home: Scaffold(
        body: ProviderReconnectRequest(
          onReconnect: onReconnect,
          child: onSourceChanged == null
              ? child
              : ProviderSourceUpdate(
                  onChanged: onSourceChanged,
                  canRebind: canRebind,
                  child: child,
                ),
        ),
      ),
    );

/// Enough of the workspace explorer for an album that holds its own files.
class _Explorer extends Fake implements WorkspaceExplorerController {
  final listeners = <VoidCallback>[];
  final loaded = <String>[];
  int refreshes = 0;

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  @override
  List<ViewPB> childrenOf(String id) => const [];

  @override
  Future<void> ensureLoaded(String id) async => loaded.add(id);

  @override
  Future<void> refresh() async => refreshes++;
}

class _DataStorage extends Fake implements ApplicationDataStorage {
  _DataStorage(this.path);
  final String path;

  @override
  Future<String> getPath() async => path;
}

class _PhotoProvider extends Fake implements CollectionProvider {
  _PhotoProvider(this.source);
  @override
  final CollectionSource source;
  ProviderFailure? failure;
  List<ProviderNode> items = const [];
  int listCalls = 0;
  bool disposed = false;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<List<ProviderNode>> listAll({
    String? parentId,
    int limit = 2000,
  }) async {
    listCalls++;
    final error = failure;
    if (error != null) {
      throw error;
    }
    return items;
  }

  @override
  void dispose() => disposed = true;
}
