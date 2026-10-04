import 'dart:async';

import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/workspace_folder/workspace_folder_stage.dart';
import 'package:appflowy/shared/document_viewer/file_action_band.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

// Author-only. Mounts the actual plain-folder remote branch, not a synthetic
// header wrapped around ExternalContentView. Only service/cache IO is replaced.
void main() {
  fileControlTestSetup();
  for (final appearance in fileControlAppearances) {
    for (final readOnly in [false, true]) {
      testWidgets('$appearance: real cloud folder header, readonly=$readOnly',
          (tester) async {
        final source = CollectionSource(
          service: ProviderService.googleDrive,
          connectionId: 'fixture-account',
          remoteId: 'remote-root',
          remoteName: 'Provider name is not the workspace title',
          readOnly: readOnly,
          options: const {'layout': 'list', 'include_hidden': true},
        );
        const cover = PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: '#D9C7A4',
        );
        final root = ViewPB(
          id: 'actual-workspace-folder',
          name: 'My cloud folder',
          parentViewId: 'workspace',
          layout: ViewLayoutPB.Document,
          icon: ViewIconPB(ty: ViewIconTypePB.Emoji, value: '📁'),
          extra: ViewCoverCodec.mergeCover(
            source.mergeIntoExtra(
              const WorkspaceItemMetadata.folder()
                  .mergeIntoExtra('{"unrelated":"retain"}'),
            ),
            cover,
          ),
        );
        final saved = root.writeToBuffer();
        final provider = _Provider();
        final listener = FileControlListener(root.id);
        final repository = _NoIdentityReads();
        ProviderController? live;
        var creations = 0;
        await mountFileControls(
          tester,
          WorkspaceFolderStage(
            view: root,
            repository: repository,
            listenerFactory: (_) => listener,
            providerControllerFactory: (id, binding) {
              creations++;
              return live = ProviderController(
                collectionId: id,
                source: binding,
                provider: provider,
                cache: _Cache(),
                autoRefresh: Duration.zero,
              );
            },
          ),
          mode: appearance,
          textScale: 2,
          width: 1000,
          height: 850,
          reduced: true,
        );
        final header = find.byType(FolderGalleryHeader, skipOffstage: false);
        final headerState = tester.state(header);
        final identity = tester.widget<FolderGalleryHeader>(header).controller;
        final page =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        expect(identity.root.id, root.id);
        expect(identity.viewForId(root.id)!.icon, root.icon);
        expect(identity.canRename(root.id), !readOnly);
        expect(
          tester.widget<ViewCoverImage>(find.byType(ViewCoverImage)).cover,
          cover,
        );
        expect(
          tester
              .widget<WorkspacePageHeader>(find.byType(WorkspacePageHeader))
              .coverView!
              .id,
          root.id,
        );
        expect(
          tester
              .widget<ViewDecorationActions>(
                find.byType(ViewDecorationActions),
              )
              .showCoverAction,
          !readOnly,
        );
        expect(find.text('My cloud folder'), findsOneWidget);
        expect(find.byType(FileActionBand), findsOneWidget);
        expect(live!.status, ProviderStatus.loading);

        EditableText? draft;
        if (!readOnly) {
          identity.beginRename(root.id);
          await settleFileControls(tester);
          final input =
              find.byKey(const ValueKey('workspace-inline-name-editor'));
          await tester.enterText(input, 'Unsaved workspace title');
          draft = tester.widget<EditableText>(input);
          draft.controller.selection =
              const TextSelection(baseOffset: 2, extentOffset: 7);
        }
        void retained() {
          expect(tester.state(header), same(headerState));
          expect(
            tester.widget<FolderGalleryHeader>(header).controller,
            same(identity),
          );
          expect(tester.state(find.byType(NestedScrollView)), same(page));
          expect(page.innerController.positions, hasLength(1));
          expect(identity.viewForId(root.id)!.extra, root.extra);
          if (draft != null) {
            expect(draft.controller.text, 'Unsaved workspace title');
            expect(
              draft.controller.selection,
              const TextSelection(baseOffset: 2, extentOffset: 7),
            );
          }
        }

        provider.next.completeError(const ProviderFailure.authExpired());
        await settleFileControls(tester);
        expect(find.byType(ProviderStateView), findsOneWidget);
        retained();
        provider.next = Completer<List<ProviderNode>>();
        final retry = live!.refresh();
        await settleFileControls(tester);
        retained();
        provider.next.complete(
          List.generate(
            100,
            (i) => ProviderNode(
              id: 'file-$i',
              name: 'Cloud file $i',
              kind: ProviderNodeKind.other,
            ),
          ),
        );
        await retry;
        await settleFileControls(tester);
        retained();
        provider.next = Completer<List<ProviderNode>>();
        final refresh = live!.refresh(silent: true);
        await tester.pump();
        provider.next.completeError(const ProviderFailure.authExpired());
        await refresh;
        await settleFileControls(tester);
        expect(find.byType(ProviderStaleBanner), findsOneWidget);
        retained();
        final outer = page.outerController.offset;
        final viewport = tester.getRect(find.byType(WorkspaceFolderStage));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: viewport.bottomCenter - const Offset(0, 30),
            scrollDelta: const Offset(0, 120),
          ),
        );
        await tester.pumpAndSettle();
        expect(page.outerController.offset, greaterThan(outer));
        expect(find.byType(ExternalContentView), findsOneWidget);
        retained();
        const changedCover = PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: '#B8C6AF',
        );
        final updated = ViewPB.fromBuffer(root.writeToBuffer())
          ..name = 'Current workspace title'
          ..icon = ViewIconPB(ty: ViewIconTypePB.Emoji, value: '📚')
          ..isLocked = true
          ..extra = ViewCoverCodec.mergeCover(root.extra, changedCover);
        listener.updated!(updated);
        await settleFileControls(tester);
        expect(
          tester.widget<FolderGalleryHeader>(header).controller,
          same(identity),
        );
        expect(tester.state(find.byType(NestedScrollView)), same(page));
        expect(identity.viewForId(root.id)!.name, updated.name);
        expect(identity.viewForId(root.id)!.icon, updated.icon);
        expect(identity.canRename(root.id), isFalse);
        expect(
          find.text('Current workspace title', skipOffstage: false),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ViewCoverImage>(
                find.byType(ViewCoverImage, skipOffstage: false),
              )
              .cover,
          changedCover,
        );
        expect(
          tester
              .widget<ViewDecorationActions>(
                find.byType(ViewDecorationActions, skipOffstage: false),
              )
              .showCoverAction,
          isFalse,
        );
        expect(identity.viewForId(root.id)!.source.options, source.options);
        expect(root.writeToBuffer(), saved);
        expect(creations, 1);
        expect(repository.calls, isEmpty);
        expect(tester.takeException(), isNull);
        await unmountFileControls(tester);
        expect(listener.stopped, isTrue);
        expect(provider.disposed, isTrue);
      });
    }
  }
}

class _NoIdentityReads extends Fake implements WorkspaceItemRepository {
  final calls = <String>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

class _Cache extends Fake implements ProviderCache {
  @override
  Future<CachedValue?> readJson(String cacheKey, String name) async => null;
  @override
  Future<void> writeJson(String cacheKey, String name, Object? value) async {}
}

class _Provider extends Fake implements CollectionProvider {
  Completer<List<ProviderNode>> next = Completer<List<ProviderNode>>();
  bool disposed = false;
  @override
  ProviderCapabilities get capabilities => ProviderCapabilities.full;
  @override
  String get originLabel => 'Fixture Drive';
  @override
  Future<void> ensureReady() async {}
  @override
  Future<List<ProviderNode>> listAll({String? parentId, int limit = 2000}) =>
      next.future;
  @override
  void dispose() => disposed = true;
}
