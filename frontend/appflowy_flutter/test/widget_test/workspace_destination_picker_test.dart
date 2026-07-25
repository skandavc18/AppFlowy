import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/move_to/workspace_destination_picker.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
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
  });

  testWidgets('move picker lists every root workspace item type', (
    tester,
  ) async {
    final source = ViewPB(
      id: 'source',
      parentViewId: 'root',
      name: 'Source note',
      layout: ViewLayoutPB.Document,
    );
    final folder = ViewPB(
      id: 'folder',
      parentViewId: 'root',
      name: 'Research',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
    final page = ViewPB(
      id: 'page',
      parentViewId: 'root',
      name: 'Project brief',
      layout: ViewLayoutPB.Document,
    );
    final table = ViewPB(
      id: 'table',
      parentViewId: 'root',
      name: 'Roadmap',
      layout: ViewLayoutPB.Grid,
    );
    final untitled = ViewPB(
      id: 'untitled',
      parentViewId: 'root',
      layout: ViewLayoutPB.Document,
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: WorkspaceDestinationPicker(
          sourceViews: [source],
          rootId: 'root',
          rootName: 'Knowledge HQ',
          operation: WorkspaceDestinationOperation.move,
          repository: _DestinationRepository([
            source,
            folder,
            page,
            table,
            untitled,
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Knowledge HQ'), findsWidgets);
    expect(find.text('Research'), findsOneWidget);
    expect(find.text('Project brief'), findsOneWidget);
    expect(find.text('Roadmap'), findsOneWidget);
    final untitledTile = find.byKey(
      const ValueKey('workspace-destination-untitled'),
    );
    expect(
      find.descendant(of: untitledTile, matching: find.text('Untitled')),
      findsOneWidget,
    );
    expect(find.text('Database'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-root-icon')), findsOneWidget);

    final tableTile = find.byKey(
      const ValueKey('workspace-destination-table'),
    );
    final tableInkWell = tester.widget<InkWell>(tableTile);
    expect(tableInkWell.onTap, isNull);

    final folderTile = find.byKey(
      const ValueKey('workspace-destination-folder'),
    );
    final folderInkWell = tester.widget<InkWell>(folderTile);
    expect(folderInkWell.onTap, isNotNull);

    await tester.tap(untitledTile);
    await tester.pump();
    expect(find.text('Untitled'), findsWidgets);

    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'Research');
    await tester.pump();
    expect(find.text('Project brief'), findsNothing);

    await tester.tap(folderTile);
    await tester.pump();
    expect(tester.widget<TextField>(searchField).controller?.text, isEmpty);
  });
}

class _DestinationRepository implements WorkspaceItemRepository {
  const _DestinationRepository(this.views);

  final List<ViewPB> views;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async =>
      FlowyResult.success(views);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
