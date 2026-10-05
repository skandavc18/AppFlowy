import 'dart:math' as math;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/extension.dart';
import 'package:appflowy/util/field_type_extension.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_find_projection.dart';
import 'package:appflowy/workspace/presentation/widgets/view_preview/view_preview_table.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

const _gridKey = ValueKey('folder-gallery-database-grid');
const _headerKey = ValueKey('folder-gallery-database-header-row');

const _ledger = FolderGalleryDatabaseSnapshot(
  columns: ['Note', 'Date', 'P&L'],
  rows: [
    ['Adjustment', 'Aug 21', '42.50'],
    ['Audit', 'Aug 22', '-7'],
  ],
  totalRowCount: 2,
  fieldTypes: [FieldType.RichText, FieldType.DateTime, FieldType.Number],
);

const _pair = FolderGalleryDatabaseSnapshot(
  columns: ['Task', 'Owner'],
  rows: [
    ['Launch website', 'Avery'],
    ['Write release notes', 'Morgan'],
  ],
  totalRowCount: 2,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('keeps grid column widths in a narrow card', (tester) async {
    await _mount(
      tester,
      const SizedBox(
        width: 185,
        height: 150,
        child: ViewPreviewTable(snapshot: _ledger),
      ),
    );

    final note = tester.getRect(find.text('Note'));
    final date = tester.getRect(find.text('Date'));
    // Three columns are not divided into 50px slivers: each keeps a grid
    // column's width, shrunk no further than three quarters.
    expect(
      date.left - note.left,
      closeTo(ViewPreviewTable.defaultColumnWidth * 0.75, 0.5),
    );
    expect(find.text('Adjustment'), findsOneWidget);
    expect(find.text('Aug 21'), findsOneWidget);
    // What does not fit runs on under a fade at the right edge.
    expect(
      find.descendant(
        of: find.byType(ViewPreviewTable),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('spans a roomy preview instead of floating inside it', (
    tester,
  ) async {
    await _mount(
      tester,
      const SizedBox(
        width: 640,
        height: 320,
        child: ViewPreviewTable(snapshot: _pair),
      ),
    );

    final preview = tester.getRect(find.byType(ViewPreviewTable));
    final grid = tester.getRect(find.byKey(_gridKey));
    expect(grid.left, closeTo(preview.left + 16, 0.5));
    expect(grid.right, closeTo(preview.right - 16, 0.5));
    expect(grid.top, closeTo(preview.top + 16, 0.5));
    // The room is shared in proportion, not handed to the last column.
    expect(
      tester.getRect(find.text('Owner')).left -
          tester.getRect(find.text('Task')).left,
      closeTo(grid.width / 2, 0.5),
    );
    expect(
      find.descendant(
        of: find.byType(ViewPreviewTable),
        matching: find.byType(ShaderMask),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the widths the table view saved', (tester) async {
    const snapshot = FolderGalleryDatabaseSnapshot(
      columns: ['Wide', 'Narrow', 'Default'],
      rows: [
        ['a', 'b', 'c'],
      ],
      totalRowCount: 1,
      widths: [260, 80, 0],
    );
    await _mount(
      tester,
      const SizedBox(
        width: 200,
        height: 160,
        child: ViewPreviewTable(snapshot: snapshot),
      ),
    );

    final wide = tester.getRect(find.text('Wide'));
    final narrow = tester.getRect(find.text('Narrow'));
    final fallback = tester.getRect(find.text('Default'));
    expect(narrow.left - wide.left, closeTo(260 * 0.75, 0.5));
    expect(fallback.left - narrow.left, closeTo(80 * 0.75, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('draws tags, checkboxes, links and field icons as the grid does',
      (tester) async {
    const snapshot = FolderGalleryDatabaseSnapshot(
      columns: ['Task', 'Labels', 'Done', 'Link'],
      rows: [
        ['Ship', 'Design, Docs', '✓', 'https://appflowy.io'],
        ['Plan', '', '', ''],
      ],
      totalRowCount: 2,
      fieldTypes: [
        FieldType.RichText,
        FieldType.MultiSelect,
        FieldType.Checkbox,
        FieldType.URL,
      ],
      options: {
        (0, 1): [
          FolderGalleryTableOption(
            name: 'Design',
            color: SelectOptionColorPB.Purple,
          ),
          FolderGalleryTableOption(
            name: 'Docs',
            color: SelectOptionColorPB.Blue,
          ),
        ],
      },
    );
    await _mount(
      tester,
      const SizedBox(
        width: 760,
        height: 240,
        child: ViewPreviewTable(snapshot: snapshot),
      ),
    );

    expect(find.text('Design, Docs'), findsNothing);
    final design = find.text('Design');
    expect(design, findsOneWidget);
    expect(find.text('Docs'), findsOneWidget);
    final tag = tester.widget<DecoratedBox>(
      find.ancestor(of: design, matching: find.byType(DecoratedBox)).first,
    );
    expect(
      (tag.decoration as BoxDecoration).color,
      SelectOptionColorPB.Purple.toColor(tester.element(design)),
    );

    expect(find.text('✓'), findsNothing);
    expect(_svg(FlowySvgs.check_filled_s), findsOneWidget);
    expect(_svg(FlowySvgs.uncheck_s), findsOneWidget);
    for (final type in snapshot.fieldTypes) {
      expect(_svg(type.svgData), findsOneWidget);
    }

    // Typed text and tags are findable; a link address is not cell text.
    expect(_findText('Ship').enabled, isTrue);
    expect(_findText('Design').enabled, isTrue);
    expect(_findText('Task').enabled, isTrue);
    expect(_findText('https://appflowy.io').enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets('$mode sheets keep the table legible', (tester) async {
      await _mount(
        tester,
        const SizedBox(
          width: 360,
          height: 220,
          child: ViewPreviewTable(snapshot: _pair),
        ),
        mode: mode,
      );

      final grid = _color(tester, _gridKey);
      final header = _color(tester, _headerKey);
      final headerText = tester.widget<Text>(find.text('Task')).style!.color!;
      final bodyText =
          tester.widget<Text>(find.text('Launch website')).style!.color!;
      expect(grid.a, 1);
      expect(header, isNot(grid));
      expect(_contrast(headerText, header), greaterThan(4.5));
      expect(_contrast(bodyText, grid), greaterThan(4.5));
      if (mode == 'dark') {
        expect(grid.computeLuminance(), lessThan(0.25));
      } else {
        expect(grid.computeLuminance(), greaterThan(0.6));
      }
      if (mode == 'paper') {
        // Paper keeps its warm sheet rather than a cool white or grey.
        expect(grid, isNot(Colors.white));
        expect(grid.r, greaterThan(grid.b));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final textScale in [1.0, 2.0]) {
    for (final size in const [
      Size(36, 28),
      Size(96, 64),
      Size(185, 120),
      Size(420, 90),
    ]) {
      testWidgets(
          'fits ${size.width.toInt()}x${size.height.toInt()} at ${textScale}x text',
          (tester) async {
        await _mount(
          tester,
          SizedBox.fromSize(
            size: size,
            child: const ViewPreviewTable(snapshot: _ledger),
          ),
          textScale: textScale,
        );

        expect(tester.getSize(find.byType(ViewPreviewTable)), size);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a narrow gallery card shows the table at a readable size', (
    tester,
  ) async {
    final table = ViewPB(
      id: 'ledger',
      name: 'Trading journal',
      layout: ViewLayoutPB.Grid,
    );
    await _mount(
      tester,
      SizedBox(
        width: 200,
        child: FolderGalleryCard(
          item: WorkspaceExplorerItem.fromView(table),
          view: table,
          preview: Future.value(
            const FolderGalleryPreview(
              kind: FolderGalleryPreviewKind.database,
              blocks: [],
              wordCount: 0,
              readingMinutes: 0,
              tags: [],
              fileTypeLabel: 'TABLE',
              database: _ledger,
            ),
          ),
          userProfile: null,
          selected: false,
          editing: false,
          onTap: () {},
          onRename: () {},
          onRenameSubmitted: (_) async => true,
          onRenameCancelled: () {},
          onMore: (_) {},
          onContextMenu: (_) {},
        ),
      ),
    );

    expect(find.byType(ViewPreviewTable), findsOneWidget);
    final note = tester.getRect(find.text('Note'));
    final date = tester.getRect(find.text('Date'));
    expect(
      date.left - note.left,
      closeTo(ViewPreviewTable.defaultColumnWidth * 0.75, 0.5),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  String mode = 'light',
  double textScale = 1,
}) async {
  final theme = DesktopAppearance().getThemeData(
    mode == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    mode == 'dark' ? Brightness.dark : Brightness.light,
    'Ahem',
    'Ahem',
  );
  await tester.pumpWidget(
    WidgetTestApp(
      child: Theme(
        data: theme,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _svg(FlowySvgData data) => find
    .byWidgetPredicate((widget) => widget is FlowySvg && widget.svg == data);

FolderGalleryFindText _findText(String text) => find
    .ancestor(
      of: find.text(text),
      matching: find.byType(FolderGalleryFindText),
    )
    .evaluate()
    .single
    .widget as FolderGalleryFindText;

Color _color(WidgetTester tester, Key key) =>
    (tester.widget<DecoratedBox>(find.byKey(key)).decoration as BoxDecoration)
        .color!;

double _contrast(Color foreground, Color background) {
  final front = Color.alphaBlend(foreground, background).computeLuminance();
  final back = background.computeLuminance();
  return (math.max(front, back) + 0.05) / (math.min(front, back) + 0.05);
}
