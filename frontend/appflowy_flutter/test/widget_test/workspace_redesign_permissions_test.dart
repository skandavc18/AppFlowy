import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/workspace/presentation/widgets/workspace_cover_actions.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/collection_plugin.dart';
import 'package:appflowy/plugins/dashboard/dashboard_plugin.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show Node;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' show MultiProvider, Provider;

import 'vivid_icon_test_support.dart';

const _titleKey = ValueKey('folder-gallery-title');
const _draftKey = ValueKey('permission-body-draft');
const _pageRoles = [
  ('viewer', ShareAccessLevel.readOnly),
  ('member', ShareAccessLevel.readAndWrite),
  ('owner', ShareAccessLevel.fullAccess),
];

void main() {
  late bool sharedSectionWasOn;
  setUpAll(prepareVividIconTestAssets);
  setUp(() async {
    sharedSectionWasOn = FeatureFlag.sharedSection.isOn;
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(_MemoryKeyValue());
    await FeatureFlag.sharedSection.turnOn();
  });
  tearDown(() async {
    await FeatureFlag.sharedSection.update(sharedSectionWasOn);
    await getIt.popScope();
  });

  for (final kind in _PluginBody.values) {
    for (final (role, level) in _pageRoles) {
      testWidgets('${kind.name}: $role access reaches the retained body',
          (tester) async {
        final view =
            ViewPB(id: 'permission-${kind.name}', name: 'Stored title');
        final access = _AccessBloc(view, level);
        final ambient = _AccessBloc(view, ShareAccessLevel.fullAccess);
        final notifier = _Notifier(view);
        final builder = _builder(kind, notifier, access);
        final body = builder.buildWidget(
          context: PluginContext(),
          shrinkWrap: false,
        );
        try {
          expect(body, isA<BlocProvider<PageAccessLevelBloc>>());
          final provider = body as BlocProvider<PageAccessLevelBloc>;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: BlocProvider<PageAccessLevelBloc>.value(
                  value: ambient,
                  child: _bodyWithLeaf(provider, const _AccessProbe()),
                ),
              ),
            ),
          );
          final nativePage = _nativePage(tester, provider);
          expect(
            nativePage,
            switch (kind) {
              _PluginBody.collection => isA<CollectionPage>(),
              _PluginBody.database => isA<DatabaseTabBarView>(),
              _PluginBody.dashboard => isA<DashboardPage>(),
            },
          );
          expect(nativePage.key, ValueKey(view.id));
          final probe = find.descendant(
            of: find.byWidget(provider),
            matching: find.byType(_AccessProbe),
          );
          expect(probe, findsOneWidget);
          expect(
            tester.element(probe).read<PageAccessLevelBloc>(),
            same(access),
          );
          expect(
            tester.widget<TextField>(find.byKey(_draftKey)).readOnly,
            role == 'viewer',
          );
          final state = tester.state<_AccessProbeState>(probe);
          final render = tester.renderObject(find.byType(EditableText));
          final selection = state.draft.selection;
          for (final next in ShareAccessLevel.values) {
            access.change(next);
            await tester.pumpAndSettle();
            expect(tester.state(probe), same(state));
            expect(
              tester.renderObject(find.byType(EditableText)),
              same(render),
            );
            final field = tester.widget<TextField>(find.byKey(_draftKey));
            expect(field.readOnly, !access.state.isEditable);
            expect(field.controller, same(state.draft));
            expect(field.controller!.text, 'Retained unsaved draft');
            expect(field.controller!.selection, selection);
          }
          access.change(ShareAccessLevel.fullAccess, locked: true);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byKey(_draftKey)).readOnly,
            isTrue,
          );
          expect(tester.state(probe), same(state));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          // The plugin, not either mounted surface, owns this bloc.
          expect(access.isClosed, isFalse);
          expect(ambient.isClosed, isFalse);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await access.close();
          await ambient.close();
          notifier.dispose();
        }
      });
    }
  }

  testWidgets('database removes the page top band but keeps embed overrides',
      (tester) async {
    final view = ViewPB(id: 'embedded-permissions', layout: ViewLayoutPB.Grid);
    final access = _AccessBloc(view, ShareAccessLevel.readOnly);
    final notifier = _Notifier(view);
    final builder = DatabasePluginWidgetBuilder(
      bloc: _ViewInfoBloc(),
      pageAccessLevelBloc: access,
      notifier: notifier,
      initialRowId: 'initial-row',
    );
    final node = Node(type: 'grid');
    try {
      expect(builder.contentPadding, EdgeInsets.zero);
      final body = builder.buildWidget(
        context: PluginContext(),
        shrinkWrap: true,
        data: {
          kDatabasePluginWidgetBuilderHorizontalPadding: 12.0,
          kDatabasePluginWidgetBuilderShowActions: true,
          kDatabasePluginWidgetBuilderNode: node,
          kDatabasePluginWidgetBuilderEmbedHeight: 384.0,
        },
      ) as BlocProvider<PageAccessLevelBloc>;
      const leaf = SizedBox(key: ValueKey('database-size-probe'));
      await tester.pumpWidget(
        MaterialApp(home: _bodyWithLeaf(body, leaf)),
      );
      final page = _nativePage(tester, body) as DatabaseTabBarView;
      expect(page.view, same(view));
      expect(page.shrinkWrap, isTrue);
      expect(page.showActions, isTrue);
      expect(page.node, same(node));
      expect(page.showPageDecoration, isFalse);
      expect(page.embedHeight, 384);
      expect(page.initialRowId, 'initial-row');
      final probe = find.descendant(
        of: find.byWidget(body),
        matching: find.byWidget(leaf),
      );
      expect(probe, findsOneWidget);
      final context = tester.element(probe);
      expect(context.read<PageAccessLevelBloc>(), same(access));
      final resolvedSize = context.read<DatabasePluginWidgetBuilderSize>();
      expect(resolvedSize.horizontalPadding, 12);
      expect(resolvedSize.verticalPadding, 16);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await access.close();
      notifier.dispose();
    }
  });

  for (final appearance in vividIconTestAppearances) {
    for (final (label, role, type, level, identity, creation) in [
      (
        'viewer',
        AFRolePB.Guest,
        WorkspaceTypePB.ServerW,
        ShareAccessLevel.readOnly,
        false,
        false,
      ),
      (
        'guest with page write access',
        AFRolePB.Guest,
        WorkspaceTypePB.ServerW,
        ShareAccessLevel.readAndWrite,
        false,
        false,
      ),
      (
        'member',
        AFRolePB.Member,
        WorkspaceTypePB.ServerW,
        ShareAccessLevel.readAndWrite,
        false,
        true,
      ),
      (
        'owner',
        AFRolePB.Owner,
        WorkspaceTypePB.ServerW,
        ShareAccessLevel.fullAccess,
        true,
        true,
      ),
      (
        'owner with read-only page access',
        AFRolePB.Owner,
        WorkspaceTypePB.ServerW,
        ShareAccessLevel.readOnly,
        false,
        false,
      ),
      (
        'local workspace',
        AFRolePB.Guest,
        WorkspaceTypePB.LocalW,
        ShareAccessLevel.fullAccess,
        true,
        true,
      ),
    ]) {
      testWidgets('$appearance: root $label separates identity from creation',
          (tester) async {
        final fixture = _GalleryFixture(role: role, type: type, level: level);
        // A real image permits Download even when all identity writes are denied.
        fixture.workspace.cover = WorkspaceCoverCodec.encode(
          const PageStyleCover(
            type: PageStyleCoverImageType.builtInImage,
            value: 'n1',
          ),
        );
        final storedCover = fixture.workspace.cover;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await tester.pumpWidget(fixture.app(appearance));
          await tester.pumpAndSettle();
          _expectHeaderPermissions(
            tester,
            identity: identity,
            creation: creation,
            hasCover: true,
          );
          expect(
            tester.widget<WorkspaceIcon>(find.byType(WorkspaceIcon)).isEditable,
            identity,
          );
          await mouse.addPointer(
            location: tester.getCenter(find.byType(WorkspacePageCover)),
          );
          await tester.pumpAndSettle();
          final download = find.widgetWithText(
            TextButton,
            LocaleKeys.document_plugins_cover_downloadCover.tr(),
          );
          expect(download.hitTestable(), findsOneWidget);
          expect(tester.widget<TextButton>(download).onPressed, isNotNull);

          final icon = find.byType(WorkspaceIcon);
          await mouse.moveTo(tester.getCenter(icon));
          await tester.pumpAndSettle();
          if (!identity) {
            await tester.tapAt(
              tester.getCenter(icon),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
            _expectHeaderPermissions(
              tester,
              identity: false,
              creation: creation,
              hasCover: true,
            );
            expect(find.byType(FlowyIconEmojiPicker), findsNothing);
            final title = tester.widget<WorkspaceInlineEditableText>(
              find.byKey(_titleKey),
            );
            expect(await title.onSubmitted('Denied rename'), isFalse);
            expect(fixture.controller.editingId, isNull);
          }
          expect(fixture.workspaceBloc.events, isEmpty);
          expect(fixture.workspace.cover, storedCover);
          expect(
            fixture.controller.root.name,
            fixture.view.name,
          );
          expect(
            PaperTheme.isEnabled(
              tester.element(find.byType(FolderGalleryHeader)),
            ),
            appearance == 'paper',
          );
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          await fixture.dispose();
        }
      });
    }

    testWidgets(
        '$appearance: a guest can edit and add inside a writable folder',
        (tester) async {
      final fixture =
          _GalleryFixture(role: AFRolePB.Guest, workspaceRoot: false);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await tester.pumpWidget(fixture.app(appearance));
        await tester.pumpAndSettle();
        _expectHeaderPermissions(
          tester,
          identity: true,
          creation: true,
          workspaceRoot: false,
        );
        final actions = tester.state(find.byType(ViewDecorationActions));
        final state = tester.state(find.byType(FolderGalleryHeader));
        fixture.access.change(ShareAccessLevel.readOnly);
        await tester.pumpAndSettle();
        final icon = find.byKey(const ValueKey('folder-gallery-title-icon'));
        await mouse.addPointer(location: tester.getCenter(icon));
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getCenter(icon),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        _expectHeaderPermissions(
          tester,
          identity: false,
          creation: false,
          workspaceRoot: false,
        );
        expect(find.byType(FlowyIconEmojiPicker), findsNothing);
        expect(tester.state(find.byType(ViewDecorationActions)), same(actions));
        expect(tester.state(find.byType(FolderGalleryHeader)), same(state));
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.dispose();
      }
    });

    testWidgets('$appearance: page and view locks override root owner rights',
        (tester) async {
      final fixture = _GalleryFixture(role: AFRolePB.Owner);
      try {
        await tester.pumpWidget(fixture.app(appearance));
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(FolderGalleryHeader));
        _expectHeaderPermissions(tester, identity: true, creation: true);
        fixture.access.change(ShareAccessLevel.fullAccess, locked: true);
        await tester.pumpAndSettle();
        _expectHeaderPermissions(tester, identity: false, creation: false);
        fixture.access.change(ShareAccessLevel.fullAccess);
        fixture.controller.updateView(
          ViewPB.fromBuffer(fixture.view.writeToBuffer())..isLocked = true,
        );
        await tester.pumpAndSettle();
        _expectHeaderPermissions(tester, identity: false, creation: false);
        expect(fixture.workspaceBloc.events, isEmpty);
        expect(tester.state(find.byType(FolderGalleryHeader)), same(state));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.dispose();
      }
    });

    testWidgets(
        '$appearance: cloud member can create and import without rename',
        (tester) async {
      final fixture = _GalleryFixture(role: AFRolePB.Member);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await tester.pumpWidget(fixture.app(appearance));
        await tester.pumpAndSettle();
        final header = find.byType(FolderGalleryHeader);
        await mouse.addPointer(location: tester.getCenter(header));
        await tester.pumpAndSettle();
        _expectHeaderPermissions(tester, identity: false, creation: true);
        await tester.tap(find.byKey(_titleKey));
        await tester.pumpAndSettle();
        expect(find.byType(WorkspaceInlineNameEditor), findsNothing);
        expect(fixture.controller.editingId, isNull);

        await tester.tap(_addButton());
        await tester.pumpAndSettle();
        final action = workspaceFileMenuActions.first;
        await tester.tap(find.widgetWithText(AppMenuRow, action.label));
        await tester.pumpAndSettle();
        expect(fixture.created, [action]);

        await mouse.moveTo(tester.getCenter(header));
        await tester.pumpAndSettle();
        await tester.tap(_addButton());
        await tester.pumpAndSettle();
        final service = ProviderServices.importable().first;
        final importRow = find.widgetWithText(AppMenuRow, service.label);
        await tester.ensureVisible(importRow);
        await tester.pumpAndSettle();
        await tester.tap(importRow);
        await tester.pumpAndSettle();
        expect(fixture.imported, [service]);
        expect(fixture.controller.root.name, fixture.view.name);
        expect(fixture.controller.editingId, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.dispose();
      }
    });
  }
}

enum _PluginBody { collection, database, dashboard }

PluginWidgetBuilder _builder(
  _PluginBody kind,
  _Notifier notifier,
  PageAccessLevelBloc access,
) =>
    switch (kind) {
      _PluginBody.collection => CollectionPluginWidgetBuilder(
          notifier: notifier,
          viewInfoBloc: _ViewInfoBloc(),
          pageAccessLevelBloc: access,
        ),
      _PluginBody.database => DatabasePluginWidgetBuilder(
          notifier: notifier,
          bloc: _ViewInfoBloc(),
          pageAccessLevelBloc: access,
        ),
      _PluginBody.dashboard => DashboardPluginWidgetBuilder(
          notifier: notifier,
          viewInfoBloc: _ViewInfoBloc(),
          pageAccessLevelBloc: access,
        ),
    };

/// Mount the returned providers themselves. MultiProvider's public contract
/// replaces their constructor children with the next provider or the test leaf,
/// so no native page state or backend listeners are started by this fixture.
Widget _bodyWithLeaf(BlocProvider<PageAccessLevelBloc> body, Widget leaf) {
  final content = body.child;
  return MultiProvider(
    providers: [
      body,
      if (content is Provider<DatabasePluginWidgetBuilderSize>) content,
    ],
    child: leaf,
  );
}

/// Inspect the public widget description without mounting the backend leaf.
/// Provider has no child getter; its built ProxyWidget exposes the page instead.
Widget _nativePage(
  WidgetTester tester,
  BlocProvider<PageAccessLevelBloc> body,
) {
  final content = body.child!;
  if (content is! Provider<DatabasePluginWidgetBuilderSize>) return content;
  final built = content.build(tester.element(find.byWidget(content)));
  expect(built, isA<ProxyWidget>());
  return (built as ProxyWidget).child;
}

class _AccessProbe extends StatefulWidget {
  const _AccessProbe();

  @override
  State<_AccessProbe> createState() => _AccessProbeState();
}

class _AccessProbeState extends State<_AccessProbe> {
  final draft = TextEditingController(text: 'Retained unsaved draft');

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        key: _draftKey,
        controller: draft,
        readOnly: !context.watch<PageAccessLevelBloc>().state.isEditable,
      );
}

class _GalleryFixture {
  _GalleryFixture({
    required AFRolePB role,
    WorkspaceTypePB type = WorkspaceTypePB.ServerW,
    ShareAccessLevel level = ShareAccessLevel.readAndWrite,
    bool workspaceRoot = true,
  }) {
    workspace = UserWorkspacePB(
      workspaceId: workspaceRoot ? view.id : 'other-workspace-root',
      name: view.name,
      workspaceType: type,
      role: role,
    );
    workspaceBloc = _WorkspaceBloc(workspace);
    access = _AccessBloc(view, level);
    controller = WorkspaceExplorerController(
      root: view,
      repository: _Repository(),
      listenForUpdates: false,
    );
  }

  final view = ViewPB(
    id: 'gallery-permissions',
    name: 'Stored gallery name',
    layout: ViewLayoutPB.Document,
    extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
  );
  late final UserWorkspacePB workspace;
  late final _WorkspaceBloc workspaceBloc;
  late final _AccessBloc access;
  late final WorkspaceExplorerController controller;
  final search = TextEditingController();
  final created = <WorkspaceFileMenuAction>[];
  final imported = <ProviderServiceInfo>[];

  Widget app(String appearance) => vividIconTestApp(
        appearance,
        MultiBlocProvider(
          providers: [
            BlocProvider<PageAccessLevelBloc>.value(value: access),
            BlocProvider<UserWorkspaceBloc>.value(value: workspaceBloc),
          ],
          child: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: controller,
              builder: (_, __) => FolderGalleryHeader(
                controller: controller,
                workspace: workspace,
                searchController: search,
                onSearchChanged: (_) {},
                onNavigate: (_) {},
                onAddFile: created.add,
                onCreateCollection: (_) {},
                onCreateDatabase: (_) {},
                onImportFromService: imported.add,
                onMore: (_) {},
              ),
            ),
          ),
        ),
      );

  Future<void> dispose() async {
    controller.dispose();
    search.dispose();
    await access.close();
    await workspaceBloc.close();
  }
}

Finder _addButton() => find.widgetWithText(
      TextButton,
      LocaleKeys.workspaceFolderExplorer_addFile.tr(),
    );

void _expectHeaderPermissions(
  WidgetTester tester, {
  required bool identity,
  required bool creation,
  bool workspaceRoot = true,
  bool hasCover = false,
}) {
  if (workspaceRoot) {
    final owner = find.byType(WorkspaceCoverActions);
    expect(owner, findsOneWidget);
    expect(tester.widget<WorkspaceCoverActions>(owner).editable, identity);
  } else {
    final owner = find.byType(ViewDecorationActions);
    expect(owner, findsOneWidget);
    final actions = tester.widget<ViewDecorationActions>(owner);
    expect(actions.showIconAction, identity);
    expect(actions.showCoverAction, identity);
    expect(actions.showDownloadAction, isTrue);
  }
  // Inspect the production composition, not a test-supplied layout builder.
  final header = tester.widget<WorkspacePageHeader>(
    find.byType(WorkspacePageHeader),
  );
  final pageIdentity = tester.widget<WorkspacePageIdentity>(
    find.byType(WorkspacePageIdentity),
  );
  expect(header.cover, hasCover ? isNotNull : isNull);
  expect(header.coverActions, hasCover ? isNotNull : isNull);
  expect(pageIdentity.iconActions, identity ? isNotNull : isNull);
  expect(pageIdentity.actions, isNotNull);
  for (final (label, present) in [
    (LocaleKeys.document_plugins_cover_addIcon, identity),
    (
      hasCover
          ? LocaleKeys.document_plugins_cover_changeCover
          : LocaleKeys.document_plugins_cover_addCover,
      identity,
    ),
    (LocaleKeys.document_plugins_cover_removeCover, identity && hasCover),
    (LocaleKeys.document_plugins_cover_downloadCover, hasCover),
  ]) {
    expect(
      find.widgetWithText(TextButton, label.tr()),
      present ? findsOneWidget : findsNothing,
    );
  }
  final title =
      tester.widget<WorkspaceInlineEditableText>(find.byKey(_titleKey));
  expect(title.onTap != null, identity);
  expect(_addButton(), creation ? findsOneWidget : findsNothing);
  for (final icon in [Icons.search_rounded, Icons.more_horiz_rounded]) {
    expect(
      find.byWidgetPredicate(
        (widget) => widget is WorkspaceGlyph && widget.icon == icon,
      ),
      findsOneWidget,
    );
  }
  expect(
    find.byKey(const ValueKey('folder-gallery-view-switcher')),
    findsOneWidget,
  );
}

class _AccessBloc extends Cubit<PageAccessLevelState>
    implements PageAccessLevelBloc {
  _AccessBloc(this.view, ShareAccessLevel level)
      : super(
          PageAccessLevelState.initial(view).copyWith(
            accessLevel: level,
            isLoadingLockStatus: false,
          ),
        );

  @override
  final ViewPB view;

  void change(ShareAccessLevel level, {bool locked = false}) => emit(
        state.copyWith(accessLevel: level, isLocked: locked),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc(UserWorkspacePB workspace)
      : super(
          UserWorkspaceState.initial(UserProfilePB()).copyWith(
            currentWorkspace: workspace,
            workspaces: [workspace],
          ),
        );

  final events = <UserWorkspaceEvent>[];

  @override
  void add(UserWorkspaceEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifier extends Fake implements ViewPluginNotifier {
  _Notifier(this.view);

  @override
  ViewPB view;

  @override
  final isDeleted = ValueNotifier<DeletedViewPB?>(null);

  @override
  void dispose() => isDeleted.dispose();
}

class _ViewInfoBloc extends Fake implements ViewInfoBloc {}

class _MemoryKeyValue extends Fake implements KeyValueStorage {
  @override
  Future<void> set(String key, String value) async {}
}

class _Repository extends Fake implements WorkspaceItemRepository {
  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async =>
      FlowyResult.success([]);
}
