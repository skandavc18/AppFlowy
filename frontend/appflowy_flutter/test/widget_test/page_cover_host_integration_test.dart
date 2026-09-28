import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart' as user;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/page_cover_test_support.dart';
import 'file_controls_test_support.dart';

const _art = PageStyleCover(
  type: PageStyleCoverImageType.builtInImage,
  value: 'n1',
);
const _grip = ValueKey('page-cover-resize');
const _hosts = ['dashboard', 'collection', 'database', 'file', 'folder'];

void main() {
  fileControlTestSetup();

  for (final theme in fileControlAppearances) {
    for (final width in [780.0, 320.0]) {
      for (final host in _hosts) {
        testWidgets(
            '$theme/$width/$host height-only release, cancel and reload',
            (tester) async {
          final fixture = _HostFixture(host);
          final store = CoverAppearanceStore(
            resolveStorage: () => CoverMemoryStorage(),
          );
          try {
            await store.ensureLoaded();
            await fixture.explorer.initialize();
            await mountFileControls(
              tester,
              fixture.scoped(store),
              mode: theme,
              width: width,
              accessible: true,
              reduced: true,
            );
            final frame = find.byType(WorkspacePageCover);
            final start = tester.getSize(frame).height;
            final title = tester.element(find.byKey(fixture.titleKey));
            final decoration = tester.state(find.byType(ViewDecorationActions));
            final image = tester.state(find.byType(Image));
            final saved = ViewCoverCodec.decodeExtra(fixture.io.view.extra);
            expect(
                PaperTheme.isEnabled(tester.element(frame)), theme == 'paper');
            expect(fixture.io.reads, 0);
            expect(find.byKey(_grip).hitTestable(), findsOneWidget);

            final cancelled = await _drag(tester);
            expect(tester.getSize(frame).height, closeTo(start + 48, .001));
            expect(fixture.io.writes, isEmpty);
            await cancelled.cancel();
            await settleFileControls(tester);
            expect(tester.getSize(frame).height, start);
            expect(fixture.io.writes, isEmpty);

            final released = await _drag(tester);
            expect(fixture.io.writes, isEmpty);
            await released.up();
            await settleFileControls(tester);
            expect(fixture.io.writes, hasLength(1));
            expect(PageCoverHeight.decode(fixture.io.view.extra), start + 48);
            expect(PageCoverHeight.decode(_hostView(tester, host).extra),
                start + 48);
            final actual = ViewCoverCodec.decodeExtra(fixture.io.view.extra)
              ..remove(PageCoverHeight.key);
            expect(actual, saved);
            expect(fixture.io.view.cover, _art);
            expect(fixture.io.view.name, 'Cover fixture');
            expect(tester.element(find.byKey(fixture.titleKey)), same(title));
            expect(tester.state(find.byType(ViewDecorationActions)),
                same(decoration));
            expect(tester.state(find.byType(Image)), same(image));
            expect(fixture.repository.renames, isEmpty);
            expect(fixture.repository.iconWrites, isEmpty);
            expect(fixture.repository.covers.saves, isEmpty);

            // Reopen the actual host over the acknowledged metadata.
            await unmountFileControls(tester);
            fixture.publish(fixture.io.view);
            await mountFileControls(tester, fixture.scoped(store),
                mode: theme, width: width, accessible: true, reduced: true);
            expect(tester.getSize(frame).height, start + 48);
            expect(fixture.io.writes, hasLength(1));
            expect(tester.takeException(), isNull);
          } finally {
            await unmountFileControls(tester);
            fixture.dispose();
            store.dispose();
          }
        }, timeout: const Timeout(Duration(seconds: 30)));
      }
    }

    for (final host in _hosts) {
      testWidgets(
          '$theme/$host live defaults and malformed height retain owners',
          (tester) async {
        final fixture = _HostFixture(host);
        final storage = CoverMemoryStorage();
        final store = CoverAppearanceStore(resolveStorage: () => storage);
        try {
          await store.ensureLoaded();
          await fixture.explorer.initialize();
          await mountFileControls(tester, fixture.scoped(store),
              mode: theme, reduced: true, accessible: true);
          final title = tester.element(find.byKey(fixture.titleKey));
          final image = tester.state(find.byType(Image));
          final titleWidget = tester.widget<WorkspaceInlineEditableText>(
            find.byKey(fixture.titleKey),
          );
          (titleWidget.onTap ?? titleWidget.onDoubleTap)!();
          await settleFileControls(tester);
          final input =
              find.byKey(const ValueKey('workspace-inline-name-editor'));
          await tester.enterText(input, 'Unfinished cover title');
          final editor = tester.widget<EditableText>(input);
          final editorState = tester.state(input);
          editor.controller.selection =
              const TextSelection(baseOffset: 2, extentOffset: 9);
          final draft = editor.controller.value;
          for (final fit in CoverImageFit.values) {
            await store.update((value) => value.copyWith(
                  corners: CoverCorners.square,
                  aspectRatio: 4,
                  fit: fit,
                  position: CoverPosition.bottom,
                ));
            await settleFileControls(tester);
            final size = tester.getSize(find.byType(WorkspacePageCover));
            expect(size.height, closeTo(size.width / 4, .001));
            expect(tester.widget<Image>(find.byType(Image)).fit,
                store.value.boxFit);
            expect(tester.widget<Image>(find.byType(Image)).alignment,
                Alignment.bottomCenter);
            final clips = find.ancestor(
              of: find.byType(ViewCoverImage),
              matching: find.byType(ClipRRect),
            );
            for (final clip in tester.widgetList<ClipRRect>(clips)) {
              expect(clip.borderRadius, BorderRadius.zero,
                  reason: 'No outer fixed-radius clip may defeat Square');
            }
            expect(tester.element(find.byKey(fixture.titleKey)), same(title));
            expect(tester.state(find.byType(Image)), same(image));
            expect(tester.state(input), same(editorState));
            expect(editor.controller.value, draft);
            expect(editor.focusNode.hasFocus, isTrue);
          }
          final map = ViewCoverCodec.decodeExtra(fixture.io.view.extra)
            ..[PageCoverHeight.key] = 'malformed';
          // Use the existing codec merge to retain the host envelope and art.
          fixture.publish(ViewPB.fromBuffer(fixture.io.view.writeToBuffer())
            ..extra = _withMalformedHeight(fixture.io.view.extra));
          await settleFileControls(tester);
          final size = tester.getSize(find.byType(WorkspacePageCover));
          expect(size.height, closeTo(size.width / 4, .001));
          expect(ViewCoverCodec.decodeExtra(fixture.io.view.extra), map);
          expect(fixture.io.writes, isEmpty);
          expect(fixture.io.view.cover, _art);
          expect(editor.controller.value, draft);
          expect(tester.state(input), same(editorState));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape,
              physicalKey: PhysicalKeyboardKey.escape);
          await settleFileControls(tester);
          expect(fixture.repository.renames, isEmpty);

          // Malformed height remains inert on a new host, not just a rebuild.
          await unmountFileControls(tester);
          await mountFileControls(tester, fixture.scoped(store),
              mode: theme, reduced: true);
          expect(tester.getSize(find.byType(WorkspacePageCover)), size);
          final positioned = ViewCoverCodec.decodeExtra(fixture.io.view.extra)
            ..[PageCoverHeight.key] = 220.5
            ..['page_cover_position'] = -.4;
          fixture.publish(ViewPB.fromBuffer(fixture.io.view.writeToBuffer())
            ..extra = jsonEncode(positioned));
          await store.update((value) => value.copyWith(
                aspectRatio: 6,
                position: CoverPosition.top,
              ));
          await settleFileControls(tester);
          expect(tester.getSize(find.byType(WorkspacePageCover)).height, 220.5);
          expect(tester.widget<Image>(find.byType(Image)).alignment,
              const Alignment(0, -.4));
          expect(fixture.io.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await unmountFileControls(tester);
          fixture.dispose();
          store.dispose();
        }
      }, timeout: const Timeout(Duration(seconds: 30)));
    }

    testWidgets(
        '$theme workspace root follows persisted defaults without a page writer',
        (tester) async {
      final fixture = _HostFixture('workspace');
      final storage = CoverMemoryStorage();
      var store = CoverAppearanceStore(resolveStorage: () => storage);
      try {
        await store.ensureLoaded();
        await fixture.explorer.initialize();
        await mountFileControls(tester, fixture.scoped(store), mode: theme);
        expect(find.byKey(_grip), findsNothing);
        expect(
            tester
                .widget<WorkspacePageHeader>(find.byType(WorkspacePageHeader))
                .coverView,
            isNull);
        await store.update((value) => value.copyWith(
              corners: CoverCorners.square,
              aspectRatio: 4,
              fit: CoverImageFit.fit,
              position: CoverPosition.top,
            ));
        await settleFileControls(tester);
        final size = tester.getSize(find.byType(WorkspacePageCover));
        expect(size.height, closeTo(size.width / 4, .001));
        expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
        expect(tester.widget<Image>(find.byType(Image)).alignment,
            Alignment.topCenter);
        final preference = store.value;
        await unmountFileControls(tester);
        store.dispose();
        store = CoverAppearanceStore(resolveStorage: () => storage);
        await store.ensureLoaded();
        await mountFileControls(tester, fixture.scoped(store), mode: theme);
        expect(store.value, preference);
        expect(tester.getSize(find.byType(WorkspacePageCover)), size);
        expect(fixture.io.reads, 0);
        expect(fixture.io.writes, isEmpty);
        expect(find.byKey(_grip), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        fixture.dispose();
        store.dispose();
      }
    });
  }

  for (final host in _hosts) {
    for (final reason in ['lock', 'cover', 'dispose']) {
      testWidgets('$host pending height preflight rejects $reason',
          (tester) async {
        final fixture = _HostFixture(host);
        final store =
            CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
        fixture.io.readGate = Completer<void>();
        try {
          await store.ensureLoaded();
          await fixture.explorer.initialize();
          await mountFileControls(tester, fixture.scoped(store), reduced: true);
          final pointer = await _drag(tester);
          await pointer.up();
          await tester.pump();
          expect(fixture.io.reads, 1);
          if (reason == 'dispose') {
            await unmountFileControls(tester);
          } else {
            final next = ViewPB.fromBuffer(fixture.io.view.writeToBuffer());
            if (reason == 'lock') {
              next.isLocked = true;
            } else {
              next.extra = ViewCoverCodec.mergeCover(
                  next.extra, const PageStyleCover.none());
            }
            fixture.publish(next);
            await settleFileControls(tester);
            expect(find.byKey(_grip), findsNothing);
            expect(find.byKey(fixture.titleKey), findsOneWidget);
          }
          fixture.io.readGate!.complete();
          await settleFileControls(tester);
          expect(fixture.io.writes, isEmpty);
          expect(PageCoverHeight.decode(fixture.io.view.extra), isNull);
          expect(tester.takeException(), isNull);
        } finally {
          if (!fixture.io.readGate!.isCompleted)
            fixture.io.readGate!.complete();
          await unmountFileControls(tester);
          fixture.dispose();
          store.dispose();
        }
      });
    }
  }

  testWidgets('file title saving disables cover resizing until its actual ACK',
      (tester) async {
    final fixture = _HostFixture('file');
    final store =
        CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
    final read = Completer<FlowyResult<ViewPB, FlowyError>>();
    fixture.repository.readGate = read.future;
    try {
      await store.ensureLoaded();
      await mountFileControls(tester, fixture.scoped(store), reduced: true);
      await clickFileControl(
          tester, find.byKey(const ValueKey('workspace-file-rename')));
      await tester.enterText(
          find.byKey(const ValueKey('workspace-inline-name-editor')),
          'Renamed.py');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleFileControls(tester);
      expect(find.byKey(_grip), findsNothing);
      expect(fixture.io.writes, isEmpty);
      expect(fixture.repository.renames, isEmpty);
      read.complete(FlowyResult.success(fixture.repository.stored));
      await settleFileControls(tester);
      expect(fixture.repository.renames, ['Renamed.py']);
      expect(find.byKey(_grip).hitTestable(), findsOneWidget);
      expect(fixture.view.value.cover, _art);
      expect(fixture.io.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      if (!read.isCompleted)
        read.complete(FlowyResult.success(fixture.repository.stored));
      await unmountFileControls(tester);
      fixture.dispose();
      store.dispose();
    }
  });

  testWidgets('dashboard immersive modes never expose a cover writer',
      (tester) async {
    final fixture = _HostFixture('dashboard');
    final store =
        CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
    try {
      await store.ensureLoaded();
      await mountFileControls(tester, fixture.scoped(store), reduced: true);
      for (final mode in [DashboardMode.focus, DashboardMode.presentation]) {
        fixture.dashboard.setMode(mode);
        await settleFileControls(tester);
        expect(find.byType(WorkspacePageCover), findsNothing);
        expect(find.byKey(_grip), findsNothing);
        expect(fixture.io.writes, isEmpty);
      }
      fixture.dashboard.setMode(DashboardMode.edit);
      await settleFileControls(tester);
      expect(find.byKey(_grip).hitTestable(), findsOneWidget);
      expect(fixture.io.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      fixture.dispose();
      store.dispose();
    }
  });

  testWidgets(
      'file resize retains the actual pending Copy owner and visible tools',
      (tester) async {
    final fixture = _HostFixture('file');
    final store =
        CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
    final pending = Completer<void>();
    fixture.repository.media.pending = pending.future;
    try {
      await store.ensureLoaded();
      await mountFileControls(tester, fixture.scoped(store), reduced: true);
      final actions = tester.state(find.byType(MediaActionButtons));
      await clickFileControl(tester, find.byKey(const ValueKey('media-copy')));
      expect(fixture.repository.media.copies, hasLength(1));
      final pointer = await _drag(tester);
      await pointer.up();
      await settleFileControls(tester);
      expect(fixture.io.writes, hasLength(1));
      expect(tester.state(find.byType(MediaActionButtons)), same(actions));
      expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('media-share')))
              .onPressed,
          isNull);
      expectFileControlPainted(
          tester, find.byKey(const ValueKey('media-copy')));
      pending.complete();
      await settleFileControls(tester);
      expect(find.byKey(const ValueKey('media-copied')), findsOneWidget);
      expect(fixture.repository.media.copies.single.source, fixture.file.path);
      expect(fixture.file.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) pending.complete();
      await unmountFileControls(tester);
      fixture.dispose();
      store.dispose();
    }
  });
}

Future<TestGesture> _drag(WidgetTester tester) async {
  final pointer = await tester.startGesture(
    tester.getCenter(find.byKey(_grip)),
    kind: PointerDeviceKind.mouse,
  );
  await pointer.moveBy(const Offset(0, 4));
  await tester.pump();
  await pointer.moveBy(const Offset(0, 44));
  await tester.pump();
  return pointer;
}

ViewPB _hostView(WidgetTester tester, String host) => host == 'file'
    ? tester
        .widget<WorkspaceFileIdentityRow>(find.byType(WorkspaceFileIdentityRow))
        .view
    : tester
        .widget<WorkspacePageHeader>(find.byType(WorkspacePageHeader))
        .coverView!;

String _withMalformedHeight(String extra) => jsonEncode(
      ViewCoverCodec.decodeExtra(extra)..[PageCoverHeight.key] = 'malformed',
    );

class _HostFixture {
  _HostFixture(this.host) {
    var extra = '{"unrelated":{"keep":true},"page_icon_size":32}';
    if (host == 'dashboard') {
      extra = DashboardMetadata(document: DashboardDocument.blank())
          .mergeIntoExtra(extra);
    } else if (host == 'collection') {
      extra =
          const CollectionMetadata(kind: CollectionKind.folder).mergeIntoExtra(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(extra),
      );
    } else if (host == 'file') {
      extra = WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: file.path,
      ).mergeIntoExtra(extra);
    } else if (host != 'database') {
      extra = const WorkspaceItemMetadata.folder().mergeIntoExtra(extra);
    }
    extra = ViewCoverCodec.mergeCover(extra, _art);
    if (host == 'database')
      extra = AutomaticViewCover.markCoverChosenByHand(extra);
    view = ValueNotifier(ViewPB(
      id: 'cover-host-$host',
      name: 'Cover fixture',
      extra: extra,
      layout: host == 'database' ? ViewLayoutPB.Grid : ViewLayoutPB.Document,
    ));
    io = CoverMemoryViews(view.value);
    repository = _Repository(view.value, file);
    explorer = WorkspaceExplorerController(
      root: view.value,
      repository: repository,
      listenForUpdates: false,
    );
    dashboard = DashboardController(
      viewId: view.value.id,
      document: DashboardDocument.blank(),
    );
  }

  final String host;
  final file = MemoryCodeFile('Untouched original');
  final search = TextEditingController();
  final binding = Object();
  late final ValueNotifier<ViewPB> view;
  late final CoverMemoryViews io;
  late final _Repository repository;
  late final WorkspaceExplorerController explorer;
  late final DashboardController dashboard;

  ValueKey<String> get titleKey => ValueKey(switch (host) {
        'dashboard' => 'dashboard-page-title',
        'collection' => 'collection-title',
        'database' => 'database-page-title',
        'file' => 'workspace-file-name',
        _ => 'folder-gallery-title',
      });

  void publish(ViewPB next) {
    io.emit(next);
    repository.stored = next;
    explorer.updateRoot(next);
    view.value = next;
  }

  Widget scoped(CoverAppearanceStore store) => CoverAppearanceScope(
        store: store,
        child: PageCoverBackendScope(
          backend: PageCoverBackendService(views: io),
          child: ValueListenableBuilder<ViewPB>(
            valueListenable: view,
            builder: (_, current, __) => switch (host) {
              'dashboard' =>
                DashboardPage(view: current, controller: dashboard),
              'collection' => CollectionPage(
                  view: current,
                  controller: explorer,
                  shellOwnsBreadcrumbs: true,
                ),
              'database' => SingleChildScrollView(
                    child: DatabasePageDecoration(
                  view: current,
                  userProfile: null,
                  horizontalPadding: 24,
                  onViewChanged: (next) => view.value = next,
                )),
              'file' => SingleChildScrollView(
                    child: WorkspaceFileIdentityRow(
                  view: current,
                  binding: binding,
                  summary: 'Original file',
                  canRename: () => !view.value.isLocked,
                  onViewChanged: (next) => view.value = next,
                  repository: repository,
                  source:
                      MediaActionSource(source: file.path, name: current.name),
                  mediaActions: repository.media,
                  fileAvailable: true,
                  actionsVisible: true,
                  coverBackend: repository.covers,
                  updateIcon: repository.writeIcon,
                )),
              _ => SingleChildScrollView(
                    child: AnimatedBuilder(
                  animation: explorer,
                  builder: (_, __) => FolderGalleryHeader(
                    controller: explorer,
                    searchController: search,
                    workspace: host == 'workspace'
                        ? user.UserWorkspacePB(
                            workspaceId: current.id,
                            name: current.name,
                            workspaceType: user.WorkspaceTypePB.LocalW,
                            cover: WorkspaceCoverCodec.encode(_art),
                          )
                        : null,
                    onSearchChanged: (_) {},
                    onNavigate: (_) {},
                    onAddFile: (_) {},
                    onCreateCollection: (_) {},
                    onCreateDatabase: (_) {},
                    onMore: (_) {},
                  ),
                )),
            },
          ),
        ),
      );

  void dispose() {
    explorer.dispose();
    dashboard.dispose();
    search.dispose();
    view.dispose();
  }
}

class _Repository extends FileControlBackend {
  _Repository(super.stored, super.file);

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
          String parentViewId) async =>
      FlowyResult.success([]);

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async =>
      FlowyResult.success([stored]);
}
