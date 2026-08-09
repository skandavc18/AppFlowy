import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/workspace_folder/workspace_folder_plugin.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_folder_header.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_folder.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_root_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('section header plus and right click share creation options', (
    tester,
  ) async {
    SidebarRootCreateKind? selected;

    await tester.pumpWidget(
      WidgetTestApp(
        child: SizedBox(
          width: 260,
          child: FolderHeader(
            title: 'Personal',
            expandButtonTooltip: 'Expand',
            addButtonTooltip: 'Add',
            onPressed: () {},
            onCreate: (kind) => selected = kind,
            onCreateFile: (_) {},
            onCreateCollection: (_) {},
            isExpanded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.addPointer(location: tester.getCenter(find.text('Personal')));
    await mouse.down(tester.getCenter(find.text('Personal')));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.text('New folder'), findsOneWidget);
    expect(find.text('New page'), findsOneWidget);
    expect(find.text('New table'), findsOneWidget);

    await tester.tap(find.text('New page'));
    await tester.pumpAndSettle();
    expect(selected, SidebarRootCreateKind.page);

    await tester.tap(find.byType(SidebarIconButton));
    await tester.pumpAndSettle();
    expect(find.text('New folder'), findsOneWidget);

    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    expect(selected, SidebarRootCreateKind.folder);
    await mouse.removePointer();
  });

  testWidgets('workspace root icon and title support inline rename', (
    tester,
  ) async {
    String? renamedTo;

    await tester.pumpWidget(
      WidgetTestApp(
        child: SizedBox(
          width: 260,
          child: FolderHeader(
            title: 'Personal',
            expandButtonTooltip: 'Expand',
            addButtonTooltip: 'Add',
            onPressed: () {},
            onCreate: (_) {},
            onCreateFile: (_) {},
            onCreateCollection: (_) {},
            isExpanded: true,
            leading: const WorkspaceRootIcon(),
            onRename: (name) async {
              renamedTo = name;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-root-icon')), findsOneWidget);
    final titleFinder = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == 'Personal',
    );
    final title = tester.widget<Text>(titleFinder);
    expect(title.style?.fontSize, SidebarTypography.headingFontSize);
    expect(
      title.style?.fontWeight,
      SidebarTypography.fontWeightForRole(SidebarTextRole.heading),
    );

    await tester.tap(find.text('Personal'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Personal'));
    await tester.pump(const Duration(milliseconds: 350));

    final editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
    expect(editor, findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    final editableText = tester.widget<EditableText>(editor);
    expect(editableText.style.fontSize, title.style?.fontSize);
    expect(editableText.style.fontWeight, title.style?.fontWeight);
    expect(editableText.style.height, title.style?.height);
    await tester.enterText(editor, 'Knowledge HQ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(renamedTo, 'Knowledge HQ');
    expect(editor, findsNothing);
  });

  testWidgets('empty sidebar space exposes root creation and valid paste', (
    tester,
  ) async {
    final clipboard = WorkspaceItemClipboard.instance
      ..copy([
        ViewPB(
          id: 'source',
          parentViewId: 'workspace',
          layout: ViewLayoutPB.Document,
        ),
      ]);
    addTearDown(clipboard.clear);

    await tester.pumpWidget(
      WidgetTestApp(
        child: SizedBox(
          width: 260,
          height: 400,
          child: SidebarBackgroundContextMenu(
            child: const Align(
              alignment: Alignment.topCenter,
              child: SizedBox(height: 40),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    const blankPosition = Offset(130, 300);
    await mouse.addPointer(location: blankPosition);
    await mouse.down(blankPosition);
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.text('New folder'), findsOneWidget);
    expect(find.text('New page'), findsOneWidget);
    expect(find.text('New table'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('child creation labels pages and tables explicitly', (
    tester,
  ) async {
    await tester.pumpWidget(const WidgetTestApp(child: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(
      ViewAddButtonActionWrapper(
        pluginBuilder: const _TestPluginBuilder(
          pluginType: PluginType.document,
          menuName: 'Document',
          layoutType: ViewLayoutPB.Document,
        ),
      ).name,
      'New page',
    );
    expect(
      ViewAddButtonActionWrapper(
        pluginBuilder: const _TestPluginBuilder(
          pluginType: PluginType.grid,
          menuName: 'Grid',
          layoutType: ViewLayoutPB.Grid,
        ),
      ).name,
      'New table',
    );
  });

  test('workspace root view routes to the folder gallery plugin', () {
    final root = workspaceRootFolderView(
      workspaceId: 'workspace',
      name: 'Knowledge HQ',
    );

    expect(root.parentViewId, isEmpty);
    expect(root.isWorkspaceFolder, isTrue);
    expect(root.plugin(), isA<WorkspaceFolderPlugin>());
  });

  testWidgets('workspace root replaces a stale same-id document plugin', (
    tester,
  ) async {
    await tester.pumpWidget(const WidgetTestApp(child: SizedBox.shrink()));

    final staleDocument = _DocumentLikePlugin('workspace');
    final manager = PageManager(plugin: staleDocument);
    final state = TabsState(pageManagers: [manager]);
    final workspaceFolder = _FolderLikePlugin('workspace');

    final updated = state.openPlugin(plugin: workspaceFolder);

    expect(updated.currentPageManager.plugin, same(workspaceFolder));
    expect(staleDocument.disposed, isTrue);
  });
}

class _TestPluginBuilder implements PluginBuilder {
  const _TestPluginBuilder({
    required this.pluginType,
    required this.menuName,
    required this.layoutType,
  });

  @override
  final PluginType pluginType;

  @override
  final String menuName;

  @override
  final ViewLayoutPB layoutType;

  @override
  FlowySvgData get icon => FlowySvgs.icon_document_s;

  @override
  Plugin build(dynamic data) => throw UnimplementedError();
}

abstract class _TestPlugin implements Plugin {
  _TestPlugin(this.id);

  @override
  final String id;

  bool disposed = false;

  @override
  PluginType get pluginType => PluginType.document;

  @override
  PluginNotifier? get notifier => null;

  @override
  PluginWidgetBuilder get widgetBuilder => throw UnimplementedError();

  @override
  void init() {}

  @override
  void dispose() => disposed = true;
}

class _DocumentLikePlugin extends _TestPlugin {
  _DocumentLikePlugin(super.id);
}

class _FolderLikePlugin extends _TestPlugin {
  _FolderLikePlugin(super.id);
}
