import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/external/external_embed_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _connection = ProviderConnection(
  id: 'external-embed-geometry-test',
  service: ProviderService.googleDrive,
  accountLabel: 'Geometry test',
);
const _following = ValueKey('following-page-element');

void main() {
  final files = MemoryFileSystem.test(
    style: Platform.isWindows ? FileSystemStyle.windows : FileSystemStyle.posix,
  );
  setUpAll(() async {
    // Seed only public connection metadata: no credentials or backend startup.
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(_ConnectionStorage());
    getIt.registerSingleton<ApplicationDataStorage>(
      _DataStorage(files.currentDirectory.path),
    );
    await ProviderConnections.instance.ensureLoaded();
  });
  tearDown(ProviderRegistry.reset);
  tearDownAll(() async {
    await ProviderConnections.instance.remove(_connection.id);
    await getIt.popScope();
  });

  Future<void> verify(
    WidgetTester tester,
    (String?, String, num?, double) sample, {
    bool resolve = false,
  }) =>
      IOOverrides.runZoned(
        () async {
          final (kind, name, storedHeight, height) = sample;
          final provider = _PendingProvider();
          ProviderRegistry.register(_connection.service, (_, __) => provider);
          final node = Node(
            type: ExternalEmbedKeys.type,
            attributes: {
              ExternalEmbedKeys.service: _connection.service.name,
              ExternalEmbedKeys.connection: _connection.id,
              ExternalEmbedKeys.nodeId: 'remote-node',
              ExternalEmbedKeys.parentId: 'parent',
              ExternalEmbedKeys.name: name,
              if (kind != null) ExternalEmbedKeys.kind: kind,
              if (storedHeight != null) ExternalEmbedKeys.height: storedHeight,
            },
          );
          final editor =
              EditorState(document: Document(root: pageNode(children: [node])))
                ..editable = false
                ..editorStyle = const EditorStyle.desktop();
          try {
            await tester.pumpWidget(
              MaterialApp(
                home: AppFlowyTheme(
                  data: AppFlowyDefaultTheme().light(fontFamily: 'Arial'),
                  child: Provider<EditorState>.value(
                    value: editor,
                    child: Scaffold(
                      body: SingleChildScrollView(
                        child: Column(
                          children: [
                            ExternalEmbedBlockComponent(
                                key: node.key, node: node),
                            const SizedBox(key: _following, height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            final media = find.byType(ResizableMedia);
            expect(tester.widget<ResizableMedia>(media).height, height);
            expect(tester.widget<ResizableMedia>(media).editable, isFalse);
            expect(provider.parents, [null]);
            expect(provider.listing.isCompleted, isFalse);
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            if (resolve) {
              final before = tester.getTopLeft(find.byKey(_following));
              final resolved = ProviderNode(
                id: 'remote-node',
                name: 'Resolved $kind',
                kind: ProviderNodeKind.values.byName(kind!),
              );
              provider.listing.complete([resolved]);
              await tester.pump();
              await tester.pump();
              final content = tester.widget<ExternalContentView>(
                find.byType(ExternalContentView),
              );
              expect(content.controller.nodeById(resolved.id), same(resolved));
              expect(content.controller.hasLoaded(resolved.id), isTrue);
              expect(provider.parents, [null, resolved.id]);
              expect(tester.widget<ResizableMedia>(media).height, height);
              expect(tester.getTopLeft(find.byKey(_following)), before);
              expect(find.byType(CircularProgressIndicator), findsNothing);
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            editor.dispose();
            expect(provider.disposed, isTrue);
          }
        },
        // Cache reads AND completion writes stay in the same in-memory FS.
        createDirectory: files.directory,
        createFile: files.file,
      );

  final codeHeight = defaultFilePreviewHeight(FilePreviewKind.code);
  final notebookHeight = defaultFilePreviewHeight(FilePreviewKind.notebook);
  for (final sample in <(String?, String, num?, double)>[
    ('folder', 'Folder', null, 340),
    ('album', 'Album', null, 340),
    ('folder', 'folder.dart', null, 340),
    ('album', 'album.ipynb', null, 340),
    ('other', 'file.bin', null, 420),
    ('unknown-kind', 'file.bin', null, 420),
    (null, 'file.bin', null, 420),
    ('code', 'main.dart', null, codeHeight),
    ('other', 'notebook.ipynb', null, notebookHeight),
    ('folder', 'folder.dart', -20, 160),
    ('album', 'album.ipynb', 1200, 900),
    ('other', 'file.bin', 515.5, 515.5),
    ('code', 'main.dart', 160, 160),
    ('other', 'notebook.ipynb', 900, 900),
  ]) {
    testWidgets(
      'stored $sample sets height before metadata',
      (tester) => verify(tester, sample),
    );
  }
  for (final kind in ['folder', 'album']) {
    testWidgets(
      '$kind metadata does not move the following page element',
      (tester) => verify(tester, (kind, kind, null, 340), resolve: true),
    );
  }
}

class _PendingProvider extends Fake implements CollectionProvider {
  final listing = Completer<List<ProviderNode>>();
  final parents = <String?>[];
  bool disposed = false;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<List<ProviderNode>> listAll({String? parentId, int limit = 2000}) {
    parents.add(parentId);
    return parentId == null ? listing.future : Future.value(const []);
  }

  @override
  void dispose() => disposed = true;
}

class _ConnectionStorage extends Fake implements KeyValueStorage {
  @override
  Future<String?> get(String key) async => key == ProviderConnections.storageKey
      ? jsonEncode([_connection.toJson()])
      : null;
  @override
  Future<void> set(String key, String value) async {}
  @override
  Future<void> remove(String key) async {}
}

class _DataStorage extends Fake implements ApplicationDataStorage {
  _DataStorage(this.path);
  final String path;
  @override
  Future<String> getPath() async => path;
}
