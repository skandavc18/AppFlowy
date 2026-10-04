import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/find/database_find_grid_navigation.dart';
import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:appflowy/plugins/database/grid/presentation/grid_scroll.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/header/desktop_field_cell.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/row/row.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/desktop_grid_text_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_builder.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_skeleton/text.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:provider/provider.dart';

import 'database_find_test_support.dart';

const findGridFarRow = 'find-row-170';
const findGridFarField = 'find-field-9';
const findGridNearRow = 'find-row-0';
const findGridNearField = 'find-field-0';

/// Real GridRow -> RowBloc -> RowContent/IntrinsicHeight -> CellContainer ->
/// EditableTextCell -> DesktopGridTextCellSkin's native TextField. Only native
/// row/cell I/O and column-presentation metadata are replaced. The lazy
/// ReorderableListView and linked grid axes use the production seek routine.
class DatabaseFindGridModel {
  DatabaseFindGridModel(this.reads, {int rowCount = 180}) {
    reads.views[databaseFindViewId]!.name = 'Grid title';
    order = [for (var i = 0; i < rowCount; i++) 'find-row-$i'];
    for (var i = 0; i < 10; i++) {
      final id = 'find-field-$i';
      final field = FieldPB(
        id: id,
        name: i == 9 ? 'Destination column' : 'Column $i',
        fieldType: FieldType.RichText,
        isPrimary: i == 0,
        // A supplied icon avoids the unrelated live property-icon lookup.
        icon: 'fixture-icon',
      );
      fields.values.add(
        FieldInfo.initial(field).copyWith(
          fieldSettings: FieldSettingsPB(
            fieldId: id,
            visibility: i == 4
                ? FieldVisibility.AlwaysHidden
                : FieldVisibility.AlwaysShown,
            width: i == 9 ? 230 : 145 + i * 7,
            wrapCellContent: i == 1,
          ),
        ),
      );
    }
    reads.fields[databaseFindViewId] =
        fields.values.map((field) => field.field).toList();
    reads.rows[databaseFindViewId] = [
      for (final id in order) RowMetaPB(id: id, isDocumentEmpty: true),
      RowMetaPB(id: 'filtered-row', isDocumentEmpty: true),
    ];
    for (var i = 0; i < order.length; i++) {
      for (var column = 0; column < 10; column++) {
        setText(
          order[i],
          'find-field-$column',
          column == 1 && i % 7 == 0
              ? 'A wrapped row with very different height. ' * (2 + i % 4)
              : 'Value $i/$column',
        );
      }
    }
    setText(findGridNearRow, findGridNearField, 'near needle cell');
    if (order.contains(findGridFarRow)) {
      setText(
        findGridFarRow,
        findGridFarField,
        '${'long prefix ' * 24}needle tail',
      );
    }
    setText(findGridNearRow, 'find-field-4', 'hidden needle sentinel');
    setText('filtered-row', findGridNearField, 'filtered needle sentinel');
    database = _Database(fields, reads.views[databaseFindViewId]!);
    builder = _Cells(this, database);
  }

  final DatabaseFindReads reads;
  final fields = _Fields();
  late List<String> order;
  late final DatabaseController database;
  late final EditableCellBuilder builder;
  final writes = <String>[];
  final openedRows = <String>[];
  final mountedCells = <CellContext, int>{};
  final gate = ValueNotifier<Completer<void>?>(null);
  final changed = ValueNotifier(0);
  final filters = <String>['retained filter'];
  final sorts = <String>['retained sort'];
  int revision = 0;

  Iterable<FieldInfo> get visibleFields => fields.values.where(
        (field) => field.visibility != FieldVisibility.AlwaysHidden,
      );

  void setText(String row, String field, String text) {
    reads.cells[(databaseFindViewId, row, field)] = CellPB(
      rowId: row,
      fieldId: field,
      fieldType: FieldType.RichText,
      data: utf8.encode(text),
    );
  }

  String text(CellContext cell) => utf8.decode(
        reads.cells[(databaseFindViewId, cell.rowId, cell.fieldId)]!.data,
      );

  CellController<String, String> cellController(CellContext cell) =>
      _CellIO(this, cell);
  RowController rowController(String rowId) => _Row(this, rowId);

  DatabaseFindViewSnapshot snapshot() => DatabaseFindViewSnapshot(
        viewId: databaseFindViewId,
        rowIds: order,
        fieldIds: visibleFields.map((field) => field.id),
        revision: revision,
      );

  void notifyLayout() {
    revision++;
    changed.value++;
  }

  void dispose() {
    final pending = gate.value;
    if (pending != null && !pending.isCompleted) pending.complete();
    gate.dispose();
    changed.dispose();
    database.compactModeNotifier.dispose();
  }
}

class DatabaseFindGridFixture extends StatefulWidget {
  const DatabaseFindGridFixture({
    super.key,
    required this.model,
    this.leadingPadding = 0,
    this.stableScrollBehavior = true,
  });
  final DatabaseFindGridModel model;
  final double leadingPadding;
  final bool stableScrollBehavior;

  @override
  State<DatabaseFindGridFixture> createState() =>
      DatabaseFindGridFixtureState();
}

class DatabaseFindGridFixtureState extends State<DatabaseFindGridFixture> {
  late final scroll = GridScrollController(
    scrollGroupController: LinkedScrollControllerGroup(),
  );
  late final headerScroll = scroll.linkHorizontalController();
  late DatabaseFindController navigation;
  final viewportKey = GlobalKey();
  final requests = <DatabaseFindRequest>[];
  final materializationSamples = <({
    DatabaseFindRequest request,
    RenderDatabaseFindAnchor? row,
    double? rowHeight,
    bool cellReady,
  })>[];
  int materializations = 0;

  String get navigationDiagnostics {
    String axis(ScrollController controller) {
      if (controller.positions.length != 1) {
        return '${controller.positions.length} attached positions';
      }
      final position = controller.position;
      return position.hasContentDimensions
          ? '${position.pixels} in '
              '[${position.minScrollExtent}, ${position.maxScrollExtent}], '
              'viewport=${position.viewportDimension}'
          : 'awaiting content dimensions';
    }

    final request = requests.isEmpty ? null : requests.last;
    final target = request?.target;
    final rows = navigation.materializedRows
        .map(
          (row) => '${row.target.rowId}(height=${row.size.height}, '
              'onstage=${row.isOnstage})',
        )
        .join(', ');
    return 'target=${target?.viewId}/${target?.rowId}/${target?.fieldId}, '
        'requestCurrent=${request?.isCurrent}, '
        'snapshotCurrent=${navigation.snapshot() == widget.model.snapshot()}, '
        'vertical=${axis(scroll.verticalController)}, '
        'horizontal=${axis(scroll.horizontalController)}, '
        'materializedRows=$rows';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    navigation = DatabaseFindScope.maybeOf(context)!;
  }

  Future<String?> _materialize(DatabaseFindRequest request) async {
    requests.add(request);
    materializations++;
    final pending = widget.model.gate.value;
    if (pending != null) await pending.future;
    if (!mounted || !request.isCurrent) return null;
    final result = await materializeDatabaseFindGridRow(
      request: request,
      vertical: scroll.verticalController,
      rowIds: () => widget.model.order,
    );
    if (!mounted || !request.isCurrent) return result;
    final rowId = request.target.rowId;
    final rows = rowId == null
        ? const <RenderDatabaseFindAnchor>[]
        : navigation
            .materializedAnchors(
              DatabaseFindTarget.row(request.target.viewId, rowId),
            )
            .toList();
    // Observe the actual handoff, not a delayed, already-settled snapshot.
    materializationSamples.add(
      (
        request: request,
        row: rows.isEmpty ? null : rows.first,
        rowHeight: rows.isEmpty ? null : rows.first.size.height,
        cellReady: navigation.materializedAnchors(request.target).isNotEmpty,
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: widget.stableScrollBehavior
            ? const _GridFindScrollBehavior()
            : const MaterialScrollBehavior(),
        child: Provider.value(
          value: const DatabasePluginWidgetBuilderSize(horizontalPadding: 40),
          child: ValueListenableBuilder<int>(
            valueListenable: widget.model.changed,
            builder: (context, _, __) {
              final model = widget.model;
              final width = model.visibleFields.fold<double>(
                40 + GridSize.newPropertyButtonWidth,
                (width, field) => width + field.width!,
              );
              return DatabaseFindLayout(
                viewId: databaseFindViewId,
                snapshot: model.snapshot,
                materialize: _materialize,
                child: Column(
                  children: [
                    const DatabaseFindAnchor(
                      target: DatabaseFindTarget.title(databaseFindViewId),
                      child: Text('Grid title'),
                    ),
                    SingleChildScrollView(
                      controller: headerScroll,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        child: Row(
                          children: [
                            const SizedBox(width: 40),
                            for (final field in model.visibleFields)
                              SizedBox(
                                width: field.width,
                                height: GridSize.headerHeight,
                                child: FieldCellButton(
                                  field: field.field,
                                  viewId: databaseFindViewId,
                                  onTap: () {},
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRect(
                        key: viewportKey,
                        child: SingleChildScrollView(
                          controller: scroll.horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: width,
                            child: ReorderableListView.builder(
                              scrollController: scroll.verticalController,
                              padding:
                                  EdgeInsets.only(top: widget.leadingPadding),
                              cacheExtent: 500,
                              buildDefaultDragHandles: false,
                              itemCount: model.order.length,
                              onReorder: (_, __) => throw StateError(
                                'Find must not reorder rows',
                              ),
                              itemBuilder: (context, index) {
                                final rowId = model.order[index];
                                return GridRow(
                                  key: ValueKey('grid_row_$rowId'),
                                  fieldController: model.fields,
                                  viewId: databaseFindViewId,
                                  rowId: rowId,
                                  rowController: _Row(model, rowId),
                                  cellBuilder: model.builder,
                                  openDetailPage: (_) =>
                                      model.openedRows.add(rowId),
                                  index: index,
                                  editable: true,
                                  cellStyleSnapshot: const PropertyStyles(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }
}

/// Keep Windows physics independent of Theme for the position-identity tests.
/// Flutter 3.27's MaterialScrollBehavior reads Theme even for the desktop
/// overscroll no-op, causing didChangeDependencies to replace ScrollPosition.
/// The separate native-behavior case deliberately exercises that replacement.
class _GridFindScrollBehavior extends MaterialScrollBehavior {
  const _GridFindScrollBehavior();

  @override
  TargetPlatform getPlatform(BuildContext context) => TargetPlatform.windows;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}

class _Fields extends Fake implements FieldController {
  final values = <FieldInfo>[];

  @override
  List<FieldInfo> get fieldInfos => List.of(values);

  @override
  FieldInfo? getField(String id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

class _Database extends Fake implements DatabaseController {
  _Database(this.fieldController, this.view);
  @override
  final FieldController fieldController;
  @override
  final ViewPB view;
  @override
  String get viewId => view.id;
  @override
  final compactModeNotifier = ValueNotifier(false);
}

class _Row extends Fake implements RowController {
  _Row(this.model, this.rowId);
  final DatabaseFindGridModel model;
  @override
  final String rowId;
  @override
  RowMetaPB get rowMeta => RowMetaPB(id: rowId, isDocumentEmpty: true);
  @override
  Future<void> initialize() async {}
  @override
  List<CellContext> loadCells() => [
        for (final field in model.fields.values)
          CellContext(rowId: rowId, fieldId: field.id),
      ];
  @override
  void addListener({OnRowChanged? onRowChanged, VoidCallback? onMetaChanged}) {}
  @override
  Future<void> dispose() async {}
}

class _Cells extends EditableCellBuilder {
  _Cells(this.model, DatabaseController database)
      : super(databaseController: database);
  final DatabaseFindGridModel model;

  @override
  EditableCellWidget buildStyled(CellContext cell, EditableCellStyle style) =>
      EditableTextCell(
        key: ValueKey(('native-find-cell', cell.rowId, cell.fieldId)),
        databaseController: databaseController,
        cellContext: cell,
        cellController: _CellIO(model, cell),
        skin: const _PlainGridSkin(),
      );
}

class _CellIO extends Fake implements CellController<String, String> {
  _CellIO(this.model, this.cell) {
    model.mountedCells.update(cell, (count) => count + 1, ifAbsent: () => 1);
  }
  final DatabaseFindGridModel model;
  final CellContext cell;
  @override
  String get viewId => databaseFindViewId;
  @override
  String get rowId => cell.rowId;
  @override
  String get fieldId => cell.fieldId;
  @override
  FieldInfo get fieldInfo => model.fields.getField(fieldId)!;
  @override
  ValueNotifier<String>? get icon => null;
  @override
  ValueNotifier<bool>? get hasDocument => null;
  @override
  String? getCellData({bool loadIfNotExist = true}) => model.text(cell);
  @override
  VoidCallback? addListener({
    required void Function(String?) onCellChanged,
    void Function(FieldInfo)? onFieldChanged,
  }) =>
      () {};
  @override
  void removeListener({
    required VoidCallback onCellChanged,
    void Function(FieldInfo)? onFieldChanged,
    VoidCallback? onRowMetaChanged,
  }) {}
  @override
  Future<void> saveCellData(
    String data, {
    bool debounce = false,
    void Function(FlowyError?)? onFinish,
  }) async {
    model.writes.add('$rowId:$fieldId:$data');
    onFinish?.call(null);
  }

  @override
  Future<void> dispose() async {}
}

/// Skip only metadata-loading wrappers. The text field builder and editable
/// skeleton are production code, not a facsimile TextField in this fixture.
class _PlainGridSkin extends IEditableTextCellSkin {
  const _PlainGridSkin();

  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    ValueNotifier<bool> compactModeNotifier,
    TextCellBloc bloc,
    FocusNode focusNode,
    TextEditingController textEditingController,
  ) =>
      Padding(
        padding: GridSize.cellContentInsets,
        child: DesktopGridTextCellSkin().buildTextField(
          context,
          focusNode: focusNode,
          controller: textEditingController,
        ),
      );
}

Finder findGridCell(String rowId, String fieldId, {bool skipOffstage = true}) =>
    find.byKey(
      ValueKey(('native-find-cell', rowId, fieldId)),
      skipOffstage: skipOffstage,
    );

Finder findGridTextField(
  String rowId,
  String fieldId, {
  bool skipOffstage = true,
}) =>
    find.descendant(
      of: findGridCell(rowId, fieldId, skipOffstage: skipOffstage),
      matching: find.byType(TextField, skipOffstage: skipOffstage),
      skipOffstage: skipOffstage,
    );

Future<void> settleDatabaseFindNavigation(
  WidgetTester tester,
  DatabaseFindController controller,
) async {
  for (var frame = 0; frame < 110; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (controller.reveal != DatabaseFindReveal.revealing) {
      await tester.pump();
      return;
    }
  }
  fail('Database navigation did not complete its bounded reveal');
}
