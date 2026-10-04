import 'dart:async';

import 'package:appflowy/plugins/database/widgets/cell_editor/extension.dart';
import 'package:appflowy/shared/table_views/list_stage.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/table_views/list_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance: one line per page, properties on the right',
        (tester) async {
      final host = _Host();
      await _pump(tester, host, appearance: appearance);

      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('4 rows'), findsOneWidget);
      for (final title in ['Write the report', 'Plan the launch', 'Ship it']) {
        expect(find.text(title), findsOneWidget);
      }
      // A page with no name still reads as one.
      expect(
        find.descendant(
          of: _row('r4'),
          matching: find.text('Untitled'),
        ),
        findsOneWidget,
      );
      expect(find.text('New page'), findsOneWidget);

      // A choice wears the colour its column gave it, exactly as the grid
      // draws it, in every appearance.
      final context = tester.element(find.byType(ListStage));
      final doing =
          find.descendant(of: _row('r1'), matching: find.text('Doing'));
      expect(doing.hitTestable(), findsOneWidget);
      final pill = tester.widget<Container>(
        find.ancestor(of: doing, matching: find.byType(Container)).first,
      );
      expect(
        (pill.decoration! as BoxDecoration).color,
        SelectOptionColorPB.Yellow.toColor(context),
      );
      expect(
        find.descendant(of: _row('r1'), matching: find.text('Ada Lovelace')),
        findsOneWidget,
      );
      expect(
        find
            .descendant(of: _row('r1'), matching: find.text('Aug 6, 2026'))
            .hitTestable(),
        findsOneWidget,
      );

      // The line answers the pointer with the appearance's own hover wash
      // rather than a fixed grey or white.
      final palette = tableViewPaletteOf(context);
      expect(palette.isPaper, appearance == 'paper');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Write the report')));
      await tester.pumpAndSettle();
      final line = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: _row('r1'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect((line.decoration! as BoxDecoration).color, palette.hover);
      expect(
        find.descendant(
          of: _row('r1'),
          matching: find.byKey(const ValueKey('list-row-more')),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Write the report'));
      await tester.pumpAndSettle();
      expect(host.opened, ['r1']);
    });
  }

  testWidgets('a narrow line drops whole properties instead of cutting one',
      (tester) async {
    await _pump(tester, _Host(), width: 600);

    expect(
      find
          .descendant(of: _row('r1'), matching: find.text('Doing'))
          .hitTestable(),
      findsOneWidget,
    );
    for (final hidden in ['Ada Lovelace', 'Aug 6, 2026']) {
      expect(
        find
            .descendant(of: _row('r1'), matching: find.text(hidden))
            .hitTestable(),
        findsNothing,
        reason: hidden,
      );
    }
    expect(find.text('Write the report').hitTestable(), findsOneWidget);
  });

  testWidgets('typing on the last line adds named pages, one after another',
      (tester) async {
    final host = _Host();
    final source = await _pump(tester, host);

    await tester.tap(find.text('New page'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('list-draft-field'));
    expect(field, findsOneWidget);

    await tester.enterText(field, 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(host.created, [
      const ListNewRow(titleColumn: 'name', title: 'Buy milk'),
    ]);
    // It shows straight away, and the line stays open for the next one.
    expect(find.text('Buy milk'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    source.readForTest(
      _table(
        extra: const [
          ['new-Buy milk', 'Buy milk', '', '', ''],
        ],
      ),
      fields: _fields(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
    expect(_row('new-Buy milk'), findsOneWidget);
    expect(find.text('5 rows'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(find.text('New page'), findsOneWidget);
    expect(host.created, hasLength(1));
  });

  testWidgets('a page that could not be made keeps its name on the line',
      (tester) async {
    final host = _Host()..create = (_) async => null;
    await _pump(tester, host);

    await tester.tap(find.text('New page'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('list-draft-field'));
    await tester.enterText(field, 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(host.created, hasLength(1));
    expect(tester.widget<TextField>(field).controller!.text, 'Buy milk');
    expect(find.byKey(const ValueKey('list-pending:0')), findsNothing);
  });

  testWidgets('grouped: option order, folding, and adding into a group',
      (tester) async {
    final host = _Host()..spec = const ListSpec(groupColumn: 'status');
    await _pump(tester, host, appearance: 'paper');

    final order = [
      for (final label in ['To do', 'Doing', 'Done', 'Everything else'])
        tester.getTopLeft(find.byKey(ValueKey('list-heading:$label'))).dy,
    ];
    expect(order, orderedEquals([...order]..sort()));
    expect(find.text('Ship it'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('list-heading:Done')),
        matching: find.text('Done'),
      ),
    );
    await tester.pumpAndSettle();
    expect(host.spec.collapsedGroups, ['Done']);
    expect(find.text('Ship it'), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('list-heading:Doing'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip('New page in Doing'),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    // The new line opens right under the heading it was asked for.
    final heading =
        tester.getBottomLeft(find.byKey(const ValueKey('list-heading:Doing')));
    final draft = tester.getTopLeft(find.byKey(const ValueKey('list-draft')));
    final firstRow = tester.getTopLeft(_row('r1'));
    expect(draft.dy, greaterThanOrEqualTo(heading.dy - 0.5));
    expect(draft.dy, lessThan(firstRow.dy));

    await tester.enterText(
      find.byKey(const ValueKey('list-draft-field')),
      'Review',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(host.created, [
      const ListNewRow(
        titleColumn: 'name',
        title: 'Review',
        groupColumn: 'status',
        groupValue: 'Doing',
      ),
    ]);
  });

  testWidgets('rename from the menu writes the name; Escape cancels',
      (tester) async {
    final host = _Host();
    await _pump(tester, host);

    Future<void> openRename() async {
      await tester.tap(
        find.text('Plan the launch'),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
    }

    await openRename();
    final field = find.byKey(const ValueKey('list-rename-field'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'Plan the launch');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(host.renamed, isEmpty);
    expect(find.text('Plan the launch'), findsOneWidget);

    await openRename();
    await tester.enterText(field, 'Plan the big launch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(host.renamed, ['r2|name|Plan the big launch']);
    expect(field, findsNothing);
    expect(find.text('Plan the big launch'), findsOneWidget);
  });

  testWidgets('a deleted page goes at once and returns if deleting fails',
      (tester) async {
    final answer = Completer<bool>();
    final host = _Host()..delete = (_) => answer.future;
    await _pump(tester, host);

    await tester.tap(
      find.text('Ship it'),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(host.deleted, ['r3']);
    expect(find.text('Ship it'), findsNothing);
    expect(find.text('3 rows'), findsOneWidget);

    answer.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Ship it'), findsOneWidget);
    expect(find.text('4 rows'), findsOneWidget);
  });

  testWidgets('the properties panel hides a property while it stays open',
      (tester) async {
    final host = _Host();
    await _pump(tester, host);

    await tester.tap(find.byKey(const ValueKey('list-properties-button')));
    await tester.pumpAndSettle();
    final owner = find.byKey(const ValueKey('list-property:owner'));
    expect(owner, findsOneWidget);
    // The title column is the line itself, not one of its properties.
    expect(find.byKey(const ValueKey('list-property:name')), findsNothing);

    await tester.tap(owner);
    await tester.pumpAndSettle();
    expect(host.spec.hiddenColumns, ['owner']);
    expect(owner, findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);

    await tester.tap(owner);
    await tester.pumpAndSettle();
    expect(host.spec.hiddenColumns, isEmpty);
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });

  testWidgets('a locked list can be read and opened but not changed',
      (tester) async {
    final host = _Host();
    await _pump(tester, host, editable: false);

    expect(find.text('New page'), findsNothing);
    await tester.tap(
      find.text('Write the report'),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Copy title'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });
}

Finder _row(String rowId) => find.byKey(ValueKey('list-row-tile:$rowId'));

class _Host {
  ListSpec spec = const ListSpec();
  final created = <ListNewRow>[];
  final renamed = <String>[];
  final deleted = <String>[];
  final opened = <String>[];
  Future<String?> Function(ListNewRow row) create =
      (row) async => 'new-${row.title}';
  Future<bool> Function(String rowId) delete = (_) async => true;
}

Future<TableRowSource> _pump(
  WidgetTester tester,
  _Host host, {
  String appearance = 'light',
  double width = 1000,
  bool editable = true,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = TableRowSource(viewId: '')
    ..readForTest(_table(), fields: _fields());
  addTearDown(source.dispose);

  await tester.pumpWidget(
    _app(
      appearance,
      StatefulBuilder(
        builder: (context, setHostState) => ListStage(
          viewId: '',
          title: 'Tasks',
          source: source,
          spec: host.spec,
          editable: editable,
          onSpecChanged: (next) => setHostState(() => host.spec = next),
          onOpenRow: host.opened.add,
          onAddRow: () async => null,
          onCreateRow: (row) {
            host.created.add(row);
            return host.create(row);
          },
          onRenameRow: (rowId, column, title) async {
            host.renamed.add('$rowId|$column|$title');
            return true;
          },
          onDuplicateRow: (_) async => true,
          onDeleteRow: (rowId) {
            host.deleted.add(rowId);
            return host.delete(rowId);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return source;
}

FieldPB _field(
  String id,
  String name,
  FieldType type, {
  bool primary = false,
  List<int> typeOption = const [],
}) =>
    FieldPB()
      ..id = id
      ..name = name
      ..fieldType = type
      ..isPrimary = primary
      ..typeOptionData = typeOption;

List<FieldPB> _fields() => [
      _field('name', 'Name', FieldType.RichText, primary: true),
      _field(
        'status',
        'Status',
        FieldType.SingleSelect,
        typeOption: (SingleSelectTypeOptionPB()
              ..options.addAll([
                SelectOptionPB(
                  id: 't',
                  name: 'To do',
                  color: SelectOptionColorPB.Blue,
                ),
                SelectOptionPB(
                  id: 'd',
                  name: 'Doing',
                  color: SelectOptionColorPB.Yellow,
                ),
                SelectOptionPB(
                  id: 'x',
                  name: 'Done',
                  color: SelectOptionColorPB.Green,
                ),
              ]))
            .writeToBuffer(),
      ),
      _field('owner', 'Owner', FieldType.RichText),
      _field('due', 'Due', FieldType.DateTime),
    ];

RepeatedRowTextPB _table({List<List<String>> extra = const []}) =>
    RepeatedRowTextPB()
      ..fieldIds.addAll(['name', 'status', 'owner', 'due'])
      ..rows.addAll([
        for (final row in [
          ['r1', 'Write the report', 'Doing', 'Ada Lovelace', 'Aug 6, 2026'],
          ['r2', 'Plan the launch', 'To do', 'Grace Hopper', ''],
          ['r3', 'Ship it', 'Done', '', ''],
          ['r4', '', '', '', ''],
          ...extra,
        ])
          RowTextPB()
            ..rowId = row.first
            ..cells.addAll(row.skip(1)),
      ]);

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Widget _app(String appearance, Widget child) => EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: _theme(appearance),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: child),
        ),
      ),
    );
