import 'dart:async';
import 'dart:ui' show PointerDeviceKind, SemanticsAction, SemanticsFlag;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_tree.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_size.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/workspace_explorer_permission_fakes.dart';
import 'vivid_icon_test_support.dart';

void main() {
  late bool sharedSectionWasOn;
  setUpAll(prepareVividIconTestAssets);
  setUp(() async {
    sharedSectionWasOn = FeatureFlag.sharedSection.isOn;
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(_MemoryKeyValue());
    await FeatureFlag.sharedSection.turnOn();
    WorkspaceItemClipboard.instance.clear();
    GalleryCardSizeStore.reset();
  });
  tearDown(() async {
    WorkspaceItemClipboard.instance.clear();
    await FeatureFlag.sharedSection.update(sharedSectionWasOn);
    await getIt.popScope();
  });

  for (final appearance in vividIconTestAppearances) {
    testWidgets(
        '$appearance: native Gallery menu disables writes, not browsing',
        (tester) async {
      final fixture = _Fixture();
      final semantics = tester.ensureSemantics();
      try {
        await _mount(tester, fixture, appearance);
        final state = tester.state(find.byType(FolderExplorer));
        final rows = fixture.controller.rows;
        final first = fixture.controller.viewForId('first');
        final search = tester
            .widget<FolderGalleryHeader>(find.byType(FolderGalleryHeader))
            .searchController;
        fixture.controller.clipboard.copy([fixture.repository.first]);
        fixture.controller.selection.selectOnly('first');
        await tester.pumpAndSettle();
        await _openBackground(tester, FolderExplorerPresentation.gallery);
        for (final label in [
          LocaleKeys.workspaceFolderExplorer_addFile.tr(),
          LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
          LocaleKeys.collections_database_table.tr(),
          LocaleKeys.collections_newCollection.tr(),
          LocaleKeys.workspaceFolderExplorer_importFile.tr(),
          LocaleKeys.workspaceFolderExplorer_paste.tr(),
          LocaleKeys.providers_connectThisFolder.tr(),
        ]) {
          expect(tester.widget<AppMenuRow>(_menu(label)).enabled, isFalse);
          final data = tester.getSemantics(_menu(label)).getSemanticsData();
          expect(data.hasFlag(SemanticsFlag.isEnabled), isFalse);
          expect(data.hasAction(SemanticsAction.tap), isFalse);
        }
        expect(
          tester
              .widget<AppMenuRow>(
                _menu(LocaleKeys.workspaceFolderExplorer_refresh.tr()),
              )
              .enabled,
          isTrue,
        );
        await tester
            .tap(_menu(LocaleKeys.workspaceFolderExplorer_newFolder.tr()));
        await tester.pumpAndSettle();
        expect(fixture.controller.draft, isNull);
        expect(fixture.repository.writes, isEmpty);
        expect(fixture.sourceConnections, 0);

        for (final mode in FileBrowserViewMode.values) {
          final choice = tester.widget<AppMenuRow>(_menu(mode.label));
          expect(choice.enabled, isTrue);
          expect(choice.selected, mode == FileBrowserViewMode.gallery);
        }
        // Seven explicit modes now follow the write actions. Tree is below
        // the menu viewport, not a two-view toggle that can be tapped in place.
        final treeChoice = _menu(FileBrowserViewMode.tree.label);
        await tester.ensureVisible(treeChoice);
        await tester.pumpAndSettle();
        expect(treeChoice.hitTestable(), findsOneWidget);
        final treeBounds = tester.getRect(treeChoice);
        final menuBounds = tester.getRect(find.byType(AppMenuSurface));
        expect(treeBounds.left, greaterThanOrEqualTo(menuBounds.left));
        expect(treeBounds.right, lessThanOrEqualTo(menuBounds.right));
        expect(treeBounds.top, greaterThanOrEqualTo(menuBounds.top));
        expect(treeBounds.bottom, lessThanOrEqualTo(menuBounds.bottom));
        final treeData = tester.getSemantics(treeChoice).getSemanticsData();
        expect(treeData.label, FileBrowserViewMode.tree.label);
        expect(treeData.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(treeData.hasFlag(SemanticsFlag.isEnabled), isTrue);
        expect(treeData.hasFlag(SemanticsFlag.isSelected), isFalse);
        expect(treeData.hasAction(SemanticsAction.tap), isTrue);
        await tester.tap(treeChoice, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.byType(ExplorerTree), findsOneWidget);
        expect(tester.state(find.byType(FolderExplorer)), same(state));
        expect(
          tester.widget<ExplorerTree>(find.byType(ExplorerTree)).controller,
          same(fixture.controller),
        );
        expect(fixture.controller.rows, same(rows));
        expect(fixture.controller.viewForId('first'), same(first));
        expect(fixture.controller.selection.ids, ['first']);
        expect(
          tester
              .widget<FolderGalleryHeader>(find.byType(FolderGalleryHeader))
              .searchController,
          same(search),
        );
        expect(
          tester
              .widget<FileBrowserViewButton>(find.byType(FileBrowserViewButton))
              .mode,
          FileBrowserViewMode.tree,
        );
        expect(fixture.controller.canWrite, isFalse);
        expect(fixture.controller.draft, isNull);
        expect(fixture.repository.writes, isEmpty);
        expect(fixture.sourceConnections, 0);
        for (final label in [
          LocaleKeys.workspaceFolderExplorer_addFile.tr(),
          LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
          LocaleKeys.workspaceFolderExplorer_paste.tr(),
        ]) {
          expect(_toolbarTarget(label), findsNothing);
        }
        expect(_internalDrags(), findsNothing);
        await tester
            .tap(_toolbarTarget(LocaleKeys.workspaceFolderExplorer_more.tr()));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AppMenuRow>(
                _menu(LocaleKeys.workspaceFolderExplorer_importFile.tr()),
              )
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<AppMenuRow>(
                _menu(LocaleKeys.workspaceFolderExplorer_selectAll.tr()),
              )
              .enabled,
          isTrue,
        );
        await _dismiss(tester);

        fixture.access.change(ShareAccessLevel.readAndWrite);
        await tester.pumpAndSettle();
        await tester.tap(
          _toolbarTarget(LocaleKeys.workspaceFolderExplorer_newFolder.tr()),
        );
        await tester.pumpAndSettle();
        expect(fixture.controller.draft, isNotNull);
        expect(fixture.controller.draft!.parentId, 'root');
        fixture.controller.cancelEditing();
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(FolderExplorer)), same(state));
        expect(
          PaperTheme.isEnabled(tester.element(find.byType(FolderExplorer))),
          appearance == 'paper',
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _dispose(tester, fixture);
      }
    });

    for (final presentation in FolderExplorerPresentation.values) {
      testWidgets('$appearance ${presentation.name}: item menu keeps Copy/Open',
          (tester) async {
        final fixture = _Fixture();
        try {
          await _mount(tester, fixture, appearance, presentation: presentation);
          await _openItemMenu(tester, presentation, 'first');
          for (final label in [
            LocaleKeys.workspaceFolderExplorer_rename.tr(),
            LocaleKeys.workspaceFolderExplorer_duplicate.tr(),
            LocaleKeys.workspaceFolderExplorer_cut.tr(),
            LocaleKeys.workspaceFolderExplorer_delete.tr(),
            if (presentation == FolderExplorerPresentation.gallery)
              LocaleKeys.workspaceFolderExplorer_showContentPreview.tr(),
          ]) {
            expect(tester.widget<AppMenuRow>(_menu(label)).enabled, isFalse);
          }
          expect(
            tester
                .widget<AppMenuRow>(
                  _menu(LocaleKeys.workspaceFolderExplorer_open.tr()),
                )
                .enabled,
            isTrue,
          );
          await tester.tap(_menu(LocaleKeys.workspaceFolderExplorer_copy.tr()));
          await tester.pumpAndSettle();
          expect(fixture.controller.clipboard.data!.views.single.id, 'first');
          await _openItemMenu(tester, presentation, 'first');
          await tester.tap(_menu(LocaleKeys.workspaceFolderExplorer_open.tr()));
          await tester.pumpAndSettle();
          expect(fixture.opened, ['first']);
          expect(fixture.repository.writes, isEmpty);

          fixture.access.change(ShareAccessLevel.readAndWrite);
          await tester.pumpAndSettle();
          await _openItemMenu(tester, presentation, 'first');
          await tester
              .tap(_menu(LocaleKeys.workspaceFolderExplorer_rename.tr()));
          await tester.pumpAndSettle();
          final editor =
              find.byKey(const ValueKey('workspace-inline-name-editor'));
          expect(editor, findsOneWidget);
          await tester.enterText(editor, 'Allowed.bin');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(fixture.repository.writes, ['rename:first']);
          expect(fixture.controller.viewForId('first')!.name, 'Allowed.bin');
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, fixture);
        }
      });

      testWidgets(
          '$appearance ${presentation.name}: keyboard and real drop gate',
          (tester) async {
        final fixture = _Fixture();
        try {
          await _mount(
            tester,
            fixture,
            appearance,
            presentation: presentation,
            externalDrag: true,
          );
          fixture.controller.selection.selectOnly('first');
          await _focusExplorer(tester, presentation);
          await _command(tester, LogicalKeyboardKey.keyC);
          final copied = fixture.controller.clipboard.data;
          expect(copied!.views.single.id, 'first');
          await _command(tester, LogicalKeyboardKey.keyX);
          await _command(tester, LogicalKeyboardKey.keyV);
          await tester.sendKeyEvent(LogicalKeyboardKey.f2);
          await tester.sendKeyEvent(LogicalKeyboardKey.delete);
          await tester.pumpAndSettle();
          expect(fixture.controller.clipboard.data, same(copied));
          expect(find.byType(WorkspaceInlineNameEditor), findsNothing);
          expect(find.byType(AlertDialog), findsNothing);
          expect(_internalDrags(), findsNothing);
          await _dropIntoFolder(tester, presentation);
          expect(fixture.repository.writes, isEmpty);

          fixture.access.change(ShareAccessLevel.readAndWrite);
          await tester.pumpAndSettle();
          expect(_internalDrags(), findsWidgets);
          await _focusExplorer(tester, presentation);
          await _command(tester, LogicalKeyboardKey.keyV);
          expect(fixture.repository.writes, ['duplicate:first:root']);
          await _dropIntoFolder(tester, presentation);
          expect(fixture.repository.writes, [
            'duplicate:first:root',
            'move:first:folder',
          ]);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, fixture);
        }
      });
    }
  }

  for (final presentation in FolderExplorerPresentation.values) {
    testWidgets('${presentation.name}: a stale writable menu cannot create',
        (tester) async {
      final fixture = _Fixture(level: ShareAccessLevel.readAndWrite);
      try {
        await _mount(tester, fixture, 'paper', presentation: presentation);
        await _openBackground(tester, presentation);
        final create = _menu(LocaleKeys.workspaceFolderExplorer_newFolder.tr());
        expect(tester.widget<AppMenuRow>(create).enabled, isTrue);
        // Deliberately no host rebuild before selecting the already-open row.
        fixture.access.change(ShareAccessLevel.readOnly);
        await tester.tap(create);
        await tester.pumpAndSettle();
        expect(fixture.controller.draft, isNull);
        expect(fixture.repository.writes, isEmpty);
        fixture.access.change(ShareAccessLevel.readAndWrite);
        await tester.pumpAndSettle();
        await _openBackground(tester, presentation);
        await tester
            .tap(_menu(LocaleKeys.workspaceFolderExplorer_newFolder.tr()));
        await tester.pumpAndSettle();
        expect(fixture.controller.draft, isNotNull);
        expect(await fixture.controller.commitDraft('Restored folder'), isTrue);
        await tester.pumpAndSettle();
        expect(fixture.repository.writes, ['createFolder:root']);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    });

    testWidgets('${presentation.name}: delete confirmation rechecks permission',
        (tester) async {
      final fixture = _Fixture(level: ShareAccessLevel.readAndWrite);
      try {
        await _mount(tester, fixture, 'light', presentation: presentation);
        fixture.controller.selection.selectOnly('first');
        await _focusExplorer(tester, presentation);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        fixture.access.change(ShareAccessLevel.readOnly);
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            LocaleKeys.workspaceFolderExplorer_delete.tr(),
          ),
        );
        await tester.pumpAndSettle();
        expect(fixture.repository.writes, isEmpty);
        expect(fixture.controller.viewForId('first'), isNotNull);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    });
  }

  testWidgets('Add submenu callback rechecks after read-only revocation',
      (tester) async {
    final fixture = _Fixture(level: ShareAccessLevel.readAndWrite);
    try {
      await _mount(tester, fixture, 'light');
      await tester.tap(
        find.widgetWithText(
          TextButton,
          LocaleKeys.workspaceFolderExplorer_addFile.tr(),
        ),
      );
      await tester.pumpAndSettle();
      fixture.access.change(ShareAccessLevel.readOnly);
      await tester.tap(_menu('Blank text file'));
      await tester.pumpAndSettle();
      expect(fixture.controller.draft, isNull);
      expect(fixture.repository.writes, isEmpty);
      expect(
        _toolbarTarget(LocaleKeys.workspaceFolderExplorer_addFile.tr()),
        findsNothing,
      );
      expect(
        _toolbarTarget(LocaleKeys.workspaceFolderExplorer_newFolder.tr()),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  testWidgets(
      'background submenu runs after dismissal and rechecks permissions',
      (tester) async {
    final fixture = _Fixture(level: ShareAccessLevel.readAndWrite);
    try {
      await _mount(tester, fixture, 'paper');
      for (final revoke in [true, false]) {
        fixture.access.change(ShareAccessLevel.readAndWrite);
        await tester.pumpAndSettle();
        await _openBackground(tester, FolderExplorerPresentation.gallery);
        await tester
            .tap(_menu(LocaleKeys.workspaceFolderExplorer_addFile.tr()));
        await tester.pumpAndSettle();
        if (revoke) fixture.access.change(ShareAccessLevel.readOnly);
        await tester.tap(_menu('Blank text file'));
        await tester.pumpAndSettle();
        expect(fixture.controller.draft, revoke ? isNull : isNotNull);
      }
      expect(fixture.controller.draft!.parentId, 'root');
      expect(fixture.repository.writes, isEmpty);
      fixture.controller.cancelEditing();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  for (final (role, type, identity, creation) in [
    (AFRolePB.Guest, WorkspaceTypePB.ServerW, false, false),
    (AFRolePB.Member, WorkspaceTypePB.ServerW, false, true),
    (AFRolePB.Owner, WorkspaceTypePB.ServerW, true, true),
    (AFRolePB.Guest, WorkspaceTypePB.LocalW, true, true),
  ]) {
    testWidgets('root $role/$type: content creation is not workspace rename',
        (tester) async {
      final fixture = _Fixture(rootRole: role, workspaceType: type);
      try {
        await _mount(tester, fixture, 'paper');
        // Synthetic workspace root has no PageAccessLevelBloc.
        expect(fixture.controller.canWrite, creation);
        expect(fixture.controller.canRename('root'), identity);
        final title = tester.widget<WorkspaceInlineEditableText>(
          find.byKey(const ValueKey('folder-gallery-title')),
        );
        expect(title.onTap != null, identity);
        await _openBackground(tester, FolderExplorerPresentation.gallery);
        final create = _menu(LocaleKeys.workspaceFolderExplorer_newFolder.tr());
        expect(tester.widget<AppMenuRow>(create).enabled, creation);
        if (creation) {
          await tester.tap(create);
          await tester.pumpAndSettle();
          expect(await fixture.controller.commitDraft('Root content'), isTrue);
          await tester.pumpAndSettle();
          expect(fixture.repository.writes, ['createFolder:root']);
        } else {
          await _dismiss(tester);
          expect(fixture.repository.writes, isEmpty);
        }
        expect(fixture.workspace!.events, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    });
  }

  testWidgets('a stale root rename submit checks the latest workspace role',
      (tester) async {
    final fixture = _Fixture(rootRole: AFRolePB.Owner);
    try {
      await _mount(tester, fixture, 'light');
      final title = tester.widget<WorkspaceInlineEditableText>(
        find.byKey(const ValueKey('folder-gallery-title')),
      );
      fixture.workspace!.changeRole(AFRolePB.Member);
      expect(await title.onSubmitted('Denied rename'), isFalse);
      expect(fixture.workspace!.events, isEmpty);
      expect(fixture.controller.canWrite, isTrue);
      expect(fixture.controller.canRename('root'), isFalse);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  testWidgets('borrowing an explorer never replaces or disposes its owner gate',
      (tester) async {
    var ownerWritable = false;
    final fixture = _Fixture(
      level: ShareAccessLevel.fullAccess,
      ownerCanWrite: () => ownerWritable,
    );
    try {
      await _mount(tester, fixture, 'light');
      expect(fixture.controller.canWrite, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.controller.canWrite, isFalse);
      ownerWritable = true;
      expect(
        await fixture.controller.createFolderImmediately(name: 'Owner'),
        isNotNull,
      );
      expect(fixture.repository.writes, ['createFolder:root']);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  testWidgets('workspace replacement cannot authorize a retained root menu',
      (tester) async {
    final fixture = _Fixture(rootRole: AFRolePB.Owner);
    try {
      await _mount(tester, fixture, 'paper');
      await _openBackground(tester, FolderExplorerPresentation.gallery);
      fixture.workspace!.replaceWorkspace('another-workspace');
      expect(fixture.controller.canWrite, isFalse);
      await tester
          .tap(_menu(LocaleKeys.workspaceFolderExplorer_newFolder.tr()));
      await tester.pumpAndSettle();
      expect(fixture.controller.draft, isNull);
      expect(fixture.repository.writes, isEmpty);
      expect(fixture.workspace!.events, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  testWidgets('unmount during drop preflight cannot reopen a borrowed gate',
      (tester) async {
    final fixture = _Fixture(level: ShareAccessLevel.fullAccess);
    try {
      await _mount(tester, fixture, 'light');
      final ancestors = Completer<List<ViewPB>>();
      fixture.repository.nextAncestors = ancestors;
      final pending = fixture.controller.moveItem(
        itemId: 'first',
        parentId: 'folder',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.controller.canWrite, isTrue);
      ancestors.complete([fixture.repository.root, fixture.repository.folder]);
      await pending;
      expect(fixture.repository.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });
}

class _Fixture {
  _Fixture({
    ShareAccessLevel level = ShareAccessLevel.readOnly,
    AFRolePB? rootRole,
    WorkspaceTypePB workspaceType = WorkspaceTypePB.ServerW,
    bool Function()? ownerCanWrite,
  }) {
    access = _AccessBloc(repository.root, level);
    controller = WorkspaceExplorerController(
      root: repository.root,
      repository: repository,
      listenForUpdates: false,
      canWrite: ownerCanWrite,
    );
    if (rootRole != null) {
      workspace = _WorkspaceBloc(
        UserWorkspacePB(
          workspaceId: repository.root.id,
          name: repository.root.name,
          workspaceType: workspaceType,
          role: rootRole,
        ),
      );
    }
  }

  final repository = ExplorerPermissionRepository();
  late final _AccessBloc access;
  late final WorkspaceExplorerController controller;
  _WorkspaceBloc? workspace;
  final opened = <String>[];
  int sourceConnections = 0;

  Widget app(
    String appearance, {
    required FolderExplorerPresentation presentation,
    required bool externalDrag,
  }) {
    Widget explorer = FolderExplorer(
      rootView: repository.root,
      controller: controller,
      initialPresentation: presentation,
      onOpen: (view) => opened.add(view.id),
      onConnectSource: () => sourceConnections++,
    );
    if (workspace case final bloc?) {
      explorer =
          BlocProvider<UserWorkspaceBloc>.value(value: bloc, child: explorer);
    } else {
      explorer = BlocProvider<PageAccessLevelBloc>.value(
        value: access,
        child: explorer,
      );
    }
    return vividIconTestApp(
      appearance,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
          child: SizedBox.expand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (externalDrag)
                  Draggable<ViewPB>(
                    key: const ValueKey('permission-external-drag'),
                    data: repository.first,
                    // The tree classifies the feedback's origin into thirds.
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    feedback: const Material(child: Text('Dragging fixture')),
                    child:
                        const SizedBox(height: 44, child: Text('Drag fixture')),
                  ),
                Expanded(child: explorer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await access.close();
    await workspace?.close();
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture,
  String appearance, {
  FolderExplorerPresentation presentation = FolderExplorerPresentation.gallery,
  bool externalDrag = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1000));
  await fixture.controller.initialize();
  await tester.pumpWidget(
    fixture.app(
      appearance,
      presentation: presentation,
      externalDrag: externalDrag,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await fixture.dispose();
  await tester.binding.setSurfaceSize(null);
}

Finder _menu(String label) => find.widgetWithText(AppMenuRow, label);

Finder _toolbarTarget(String tooltip) => find.descendant(
      of: find.byType(FolderGalleryHeader),
      matching: find.byTooltip(tooltip),
    );

Finder _internalDrags() => find.descendant(
      of: find.byType(FolderExplorer),
      matching: find.byWidgetPredicate(
        (widget) => widget is Draggable<ViewPB>,
      ),
    );

Finder _item(FolderExplorerPresentation presentation, String id) => find.byKey(
      ValueKey(
        presentation == FolderExplorerPresentation.gallery
            ? 'gallery-card-$id'
            : id,
      ),
    );

Future<void> _openBackground(
  WidgetTester tester,
  FolderExplorerPresentation presentation,
) async {
  if (presentation == FolderExplorerPresentation.gallery) {
    final trigger = find.byKey(const ValueKey('folder-gallery-options'));
    final glyph =
        find.descendant(of: trigger, matching: find.byType(WorkspaceGlyph));
    final focus = Focus.of(tester.element(glyph));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await tester.tapAt(
      tester.getBottomRight(find.byType(ExplorerTree)) - const Offset(24, 24),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _openItemMenu(
  WidgetTester tester,
  FolderExplorerPresentation presentation,
  String id,
) async {
  final item = _item(presentation, id);
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tapAt(
    tester.getCenter(item),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

Future<void> _focusExplorer(
  WidgetTester tester,
  FolderExplorerPresentation presentation,
) async {
  final label = presentation == FolderExplorerPresentation.gallery
      ? 'folder-gallery'
      : 'folder-explorer-tree';
  final focus = tester
      .widget<Focus>(
        find.byWidgetPredicate(
          (widget) => widget is Focus && widget.focusNode?.debugLabel == label,
        ),
      )
      .focusNode!;
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue);
}

Future<void> _command(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _dismiss(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

Future<void> _dropIntoFolder(
  WidgetTester tester,
  FolderExplorerPresentation presentation,
) async {
  final target = _item(presentation, 'folder');
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const ValueKey('permission-external-drag'))),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(const Offset(0, 20));
  await tester.pump();
  final destination = tester.getCenter(target);
  await gesture.moveTo(destination - const Offset(0, 2));
  await tester.pump();
  await gesture.moveTo(destination);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
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

  void change(ShareAccessLevel level) =>
      emit(state.copyWith(accessLevel: level));

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

  void changeRole(AFRolePB role) {
    final workspace = UserWorkspacePB.fromBuffer(
      state.currentWorkspace!.writeToBuffer(),
    )..role = role;
    emit(state.copyWith(currentWorkspace: workspace));
  }

  void replaceWorkspace(String id) {
    final workspace = UserWorkspacePB.fromBuffer(
      state.currentWorkspace!.writeToBuffer(),
    )..workspaceId = id;
    emit(state.copyWith(currentWorkspace: workspace));
  }

  @override
  void add(UserWorkspaceEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryKeyValue implements KeyValueStorage {
  final values = <String, String>{};

  @override
  Future<void> set(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> clear() async => values.clear();
}
