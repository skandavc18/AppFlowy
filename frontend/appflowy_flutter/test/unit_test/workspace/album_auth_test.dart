import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/external_collection_host.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/collection/views/album/album_host.dart';
import 'package:appflowy/plugins/collection/views/album/album_thumbnail.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
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

void main() {
  late Directory cacheRoot;
  late CollectionSource source;
  late ProviderFailure? nextFailure;
  final created = <_PhotoProvider>[];
  var selection = 0;

  setUpAll(() async {
    cacheRoot = await Directory.systemTemp.createTemp('appflowy-album-auth-');
    getIt.registerSingleton<ApplicationDataStorage>(
        _DataStorage(cacheRoot.path),);
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
    created.clear();
    ProviderRegistry.register(ProviderService.googlePhotos, (_, source) {
      final provider = _PhotoProvider(source)..failure = nextFailure;
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
}

CollectionViewContext _collection(
  CollectionSource source, [
  CollectionViewDefinition? definition,
]) =>
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
      explorer: _UnusedExplorer(),
      onOpen: (_) {},
      onOpenView: (_) {},
      onStateChanged: (_, __) {},
    );

Widget _app({
  required ValueChanged<CollectionSource> onReconnect,
  required Widget child,
  Brightness brightness = Brightness.light,
  bool paper = false,
}) =>
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: [PaperThemeExtension(enabled: paper)],
      ),
      home: Scaffold(
        body: ProviderReconnectRequest(onReconnect: onReconnect, child: child),
      ),
    );

class _UnusedExplorer extends Fake implements WorkspaceExplorerController {
  @override
  void removeListener(VoidCallback listener) {}
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
  int listCalls = 0;
  bool disposed = false;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<List<ProviderNode>> listAll(
      {String? parentId, int limit = 2000,}) async {
    listCalls++;
    final error = failure;
    if (error != null) {
      throw error;
    }
    return const [];
  }

  @override
  void dispose() => disposed = true;
}
