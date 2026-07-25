import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/mobile/presentation/search/view_ancestor_cache.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/workspace_folder/workspace_folder_plugin.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/page_inspection_panel.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_result_cell.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_results_list.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    if (!getIt.isRegistered<ViewAncestorCache>()) {
      getIt.registerSingleton<ViewAncestorCache>(_EmptyViewAncestorCache());
    }
  });

  tearDownAll(() async {
    if (getIt.isRegistered<ViewAncestorCache>()) {
      await getIt.unregister<ViewAncestorCache>();
    }
  });

  testWidgets('folder search preview browses nested children recursively', (
    tester,
  ) async {
    final root = _folder('root', '', 'Research');
    final nested = _folder('nested', root.id, 'Interviews');
    root.extra = ViewCoverCodec.mergeCover(
      root.extra,
      const PageStyleCover(
        type: PageStyleCoverImageType.pureColor,
        value: '#D9C7A4',
      ),
    );
    nested.extra = ViewCoverCodec.mergeCover(
      nested.extra,
      const PageStyleCover(
        type: PageStyleCoverImageType.gradientColor,
        value: 'sunset',
      ),
    );
    final page = ViewPB(
      id: 'page',
      parentViewId: root.id,
      name: 'Research brief',
      layout: ViewLayoutPB.Document,
    );
    final table = ViewPB(
      id: 'table',
      parentViewId: root.id,
      name: 'Sources',
      layout: ViewLayoutPB.Grid,
    );
    final nestedPage = ViewPB(
      id: 'nested-page',
      parentViewId: nested.id,
      name: 'Customer call',
      layout: ViewLayoutPB.Document,
    );
    ViewPB? opened;

    await tester.pumpWidget(
      WidgetTestApp(
        child: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: Builder(
            builder: (context) => Theme(
              data: Theme.of(context).copyWith(
                extensions: [
                  ...Theme.of(context).extensions.values,
                  const PaperThemeExtension(enabled: true),
                ],
              ),
              child: SizedBox(
                width: 520,
                height: 680,
                child: PageInspectionPanel(
                  view: root,
                  cachedViews: {
                    root.id: root,
                    nested.id: nested,
                    page.id: page,
                    table.id: table,
                    nestedPage.id: nestedPage,
                  },
                  currentUserId: null,
                  onOpen: (view) => opened = view,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ViewCoverImage), findsOneWidget);
    expect(find.byType(FolderGalleryCollectionArtwork), findsNothing);
    expect(
      tester
          .widget<ViewCoverImage>(
            find.byKey(const ValueKey('command-palette-folder-cover')),
          )
          .cover,
      root.cover,
    );
    expect(find.text('Interviews'), findsOneWidget);
    expect(find.text('Research brief'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('command-palette-folder-child-nested'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer call'), findsOneWidget);
    expect(find.text('Research brief'), findsNothing);
    expect(
      tester
          .widget<ViewCoverImage>(
            find.byKey(const ValueKey('command-palette-folder-cover')),
          )
          .cover,
      nested.cover,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('command-palette-folder-child-nested-page'),
      ),
    );
    expect(opened?.id, nestedPage.id);
  });

  testWidgets('narrow search opens an in-pane recursive folder browser', (
    tester,
  ) async {
    final root = _folder('root', '', 'Research');
    final nested = _folder('nested', root.id, 'Interviews');
    final nestedPage = ViewPB(
      id: 'nested-page',
      parentViewId: nested.id,
      name: 'Customer call',
      layout: ViewLayoutPB.Document,
    );
    final result = SearchResultItem(
      id: root.id,
      icon: ResultIconPB(),
      content: '',
      displayName: root.name,
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: SizedBox(
            width: 600,
            height: 560,
            child: SearchResultList(
              cachedViews: {
                root.id: root,
                nested.id: nested,
                nestedPage.id: nestedPage,
              },
              resultItems: [result],
              resultSummaries: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchResultCell));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('command-palette-folder-browser-back')),
      findsOneWidget,
    );
    expect(find.byType(FolderGalleryCollectionArtwork), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('command-palette-folder-child-nested'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Customer call'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('command-palette-folder-browser-back')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('command-palette-search-results-panel')),
      findsOneWidget,
    );
  });

  testWidgets('raw workspace search result renders the folder preview', (
    tester,
  ) async {
    final root = ViewPB(
      id: 'workspace',
      parentViewId: '',
      name: 'Backend workspace root',
      layout: ViewLayoutPB.Document,
    );
    final child = ViewPB(
      id: 'page',
      parentViewId: root.id,
      name: 'Project brief',
      layout: ViewLayoutPB.Document,
    );
    final result = SearchResultItem(
      id: root.id,
      icon: ResultIconPB(),
      content: '',
      displayName: 'Knowledge HQ',
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: SizedBox(
            width: 900,
            height: 620,
            child: SearchResultList(
              cachedViews: {
                root.id: root,
                child.id: child,
              },
              resultItems: [result],
              resultSummaries: const [],
              currentWorkspaceId: root.id,
              currentWorkspaceName: 'Knowledge HQ',
              currentWorkspaceIcon: '🚀',
              currentWorkspaceCover: const PageStyleCover(
                type: PageStyleCoverImageType.pureColor,
                value: '#C0D7B7',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panel = tester.widget<PageInspectionPanel>(
      find.byType(PageInspectionPanel),
    );
    expect(panel.view.isWorkspaceRootFolder, isTrue);
    expect(panel.view.name, 'Knowledge HQ');
    expect(panel.view.icon.value, '🚀');
    expect(
      panel.view.cover,
      const PageStyleCover(
        type: PageStyleCoverImageType.pureColor,
        value: '#C0D7B7',
      ),
    );
    final renderedIcon = find.descendant(
      of: find.byType(SearchResultCell),
      matching: find.byType(RawEmojiIconWidget),
    );
    expect(renderedIcon, findsOneWidget);
    expect(
      tester.widget<RawEmojiIconWidget>(renderedIcon).emoji.emoji,
      '🚀',
    );
    expect(find.byType(ViewCoverImage), findsOneWidget);
    expect(find.byType(FolderGalleryCollectionArtwork), findsNothing);
    expect(find.text('Project brief'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
  });

  test('workspace search navigation opens the gallery without setting latest',
      () async {
    final menuSharedState = MenuSharedState();
    getIt.registerSingleton<MenuSharedState>(menuSharedState);
    getIt.registerSingleton<PluginSandbox>(PluginSandbox());
    final tabsBloc = TabsBloc();
    getIt.registerSingleton<TabsBloc>(tabsBloc);
    addTearDown(() async {
      await tabsBloc.close();
      await getIt.unregister<TabsBloc>();
      await getIt.unregister<PluginSandbox>();
      await getIt.unregister<MenuSharedState>();
    });
    final root = ViewPB(
      id: 'workspace',
      parentViewId: '',
      name: 'Backend workspace root',
      layout: ViewLayoutPB.Document,
    ).asWorkspaceRootFolder(
      workspaceId: 'workspace',
      name: 'Knowledge HQ',
    );
    final opened = tabsBloc.stream.firstWhere(
      (state) => state.currentPageManager.plugin is WorkspaceFolderPlugin,
    );

    root.navigateTo();
    await opened;

    expect(
      tabsBloc.state.currentPageManager.plugin,
      isA<WorkspaceFolderPlugin>(),
    );
    expect(menuSharedState.latestOpenView, isNull);
  });
}

ViewPB _folder(String id, String parentId, String name) => ViewPB(
      id: id,
      parentViewId: parentId,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );

class _EmptyViewAncestorCache extends ViewAncestorCache {
  @override
  Future<ViewAncestor?> getAncestor(
    String viewId, {
    ValueChanged<ViewAncestor>? onRefresh,
  }) async {
    return const ViewAncestor.empty();
  }
}
