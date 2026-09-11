import 'dart:typed_data';

import 'package:appflowy/ai/tools/document_toolkit.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/date_cell_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/domain/select_option_cell_service.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:nanoid/nanoid.dart';

/// What applying a template produced.
class TemplateOutcome {
  const TemplateOutcome({required this.primary, required this.created});

  /// The thing to open afterwards: the folder for a template of several
  /// parts, otherwise the one thing it made.
  final ViewPB primary;

  /// Every view the template made, in the order it made them.
  final List<ViewPB> created;
}

/// Turns a template into real pages, dashboards and tables.
///
/// Nothing it makes is marked as coming from a template: a page made this way
/// is an ordinary page, so it can be renamed, moved, rewritten or thrown away
/// exactly like any other.
abstract final class TemplateService {
  /// Builds [template] under [parentViewId].
  ///
  /// A template of several parts is given a folder of its own to live in, so
  /// a dashboard and the table it reads arrive together instead of being
  /// scattered across the sidebar.
  static Future<TemplateOutcome?> create({
    required String parentViewId,
    required WorkspaceTemplate template,
    ViewSectionPB? section,
  }) async {
    final parts = template.parts;
    if (parts.isEmpty) {
      return null;
    }

    var parent = parentViewId;
    ViewPB? holder;
    if (parts.length > 1) {
      final folder = await const WorkspaceItemService()
          .createFolder(
            parentViewId: parentViewId,
            name: template.label(),
            section: section,
          )
          .fold((view) => view, (_) => null);
      if (folder == null) {
        return null;
      }
      holder = folder;
      parent = folder.id;
    }

    final created = <ViewPB>[];
    final ids = <String, String>{};
    for (final part in parts) {
      final view = await _buildPart(
        parentViewId: parent,
        part: part,
        // Only a part already made can be referred to, so a dashboard binding
        // to a table has to be listed after it.
        created: Map.unmodifiable(ids),
        // Parts inside a folder inherit its section.
        section: holder == null ? section : null,
      );
      if (view == null) {
        continue;
      }
      created.add(view);
      ids[part.key] = view.id;
      if (part.icon.isNotEmpty) {
        await ViewBackendService.updateViewIcon(
          view: view,
          viewIcon: EmojiIconData.emoji(part.icon),
        );
      }
    }

    if (created.isEmpty) {
      return null;
    }
    return TemplateOutcome(primary: holder ?? created.first, created: created);
  }

  /// Lays a single-part template over a view that already exists.
  ///
  /// A dashboard or canvas is replaced outright — its arrangement IS the thing
  /// being changed. A page is APPENDED to, because whatever somebody already
  /// wrote there is not the template's to throw away.
  static Future<bool> applyTo({
    required ViewPB view,
    required WorkspaceTemplate template,
  }) async {
    final parts = template.parts;
    if (parts.length != 1 || !template.appliesTo(view)) {
      return false;
    }

    // The extra also carries the cover, the icon and every other mark, so it
    // has to be re-read and merged into rather than replaced.
    final current = await ViewBackendService.getView(view.id)
        .fold((found) => found, (_) => null);
    final extra = current?.extra ?? view.extra;

    switch (parts.single.blueprint) {
      case TemplateDashboard(build: final build):
        final result = await ViewBackendService.updateView(
          viewId: view.id,
          extra: DashboardMetadata(document: build(const {}))
              .mergeIntoExtra(extra),
        );
        return result.fold((_) => true, (_) => false);

      case TemplateCanvas(build: final build):
        final result = await ViewBackendService.updateView(
          viewId: view.id,
          extra:
              CanvasMetadata(document: build(const {})).mergeIntoExtra(extra),
        );
        return result.fold((_) => true, (_) => false);

      case TemplatePage(markdown: final markdown):
        return _appendMarkdown(view.id, markdown(const {}));

      case TemplateDatabase():
      case TemplateFolder():
        return false;
    }
  }

  // ---------------------------------------------------------------- the parts

  static Future<ViewPB?> _buildPart({
    required String parentViewId,
    required TemplatePart part,
    required TemplateContext created,
    ViewSectionPB? section,
  }) async {
    final name = part.name();
    switch (part.blueprint) {
      case TemplateDashboard(build: final build):
        return _create(
          layout: ViewLayoutPB.Document,
          parentViewId: parentViewId,
          name: name,
          section: section,
          extra: DashboardMetadata.newExtra(document: build(created)),
        );

      case TemplateCanvas(build: final build):
        return _create(
          layout: ViewLayoutPB.Document,
          parentViewId: parentViewId,
          name: name,
          section: section,
          extra: CanvasMetadata.newExtra(document: build(created)),
        );

      case TemplateFolder():
        return const WorkspaceItemService()
            .createFolder(
              parentViewId: parentViewId,
              name: name,
              section: section,
            )
            .fold((view) => view, (_) => null);

      case TemplatePage(markdown: final markdown):
        return _create(
          layout: ViewLayoutPB.Document,
          parentViewId: parentViewId,
          name: name,
          section: section,
          initialDataBytes: _documentBytes(markdown(created)),
        );

      case TemplateDatabase(build: final build, layout: final layout):
        final view = await _create(
          layout: layout,
          parentViewId: parentViewId,
          name: name,
          section: section,
        );
        if (view != null) {
          await buildTable(viewId: view.id, table: build(created));
        }
        return view;
    }
  }

  static Future<ViewPB?> _create({
    required ViewLayoutPB layout,
    required String parentViewId,
    required String name,
    ViewSectionPB? section,
    String? extra,
    Uint8List? initialDataBytes,
  }) async {
    final result = await ViewBackendService.createView(
      layoutType: layout,
      parentViewId: parentViewId,
      name: name,
      section: section,
      extra: extra,
      initialDataBytes: initialDataBytes,
    );
    return result.fold(
      (view) => view,
      (error) {
        Log.warn('[Template] "$name" was not created: ${error.msg}');
        return null;
      },
    );
  }

  // ------------------------------------------------------------------- pages

  static Uint8List? _documentBytes(String markdown) {
    if (markdown.trim().isEmpty) {
      return null;
    }
    final document = DocumentToolkit().parseMarkdown(markdown);
    return DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
  }

  static Future<bool> _appendMarkdown(String pageId, String markdown) async {
    final toolkit = DocumentToolkit();
    final data = await toolkit.open(pageId);
    if (data == null) {
      return false;
    }
    final nodes = toolkit.parseMarkdown(markdown).root.children;
    if (nodes.isEmpty) {
      return false;
    }
    final written = await toolkit.insert(
      pageId: pageId,
      nodes: nodes,
      parentId: data.pageId,
      previousId: toolkit.lastTopLevelBlockId(data),
    );
    if (written == 0) {
      return false;
    }
    // A backend write reaches an open editor only when it is asked to re-read.
    await DocumentBloc.findOpen(pageId)?.forceReloadDocumentState();
    return true;
  }

  // --------------------------------------------------------------- databases

  /// Gives a freshly made database the columns and example rows a template
  /// asked for.
  ///
  /// ⚠️ The first column has to be text: it is the database's primary field,
  /// and the backend refuses to retype that one.
  static Future<void> buildTable({
    required String viewId,
    required TemplateTable table,
  }) async {
    if (table.columns.isEmpty) {
      return;
    }

    final primary = await FieldBackendService.getPrimaryField(viewId: viewId)
        .fold((field) => field, (_) => null);
    if (primary == null) {
      Log.warn('[Template] $viewId has no primary column to name.');
      return;
    }
    await FieldBackendService(viewId: viewId, fieldId: primary.id)
        .updateField(name: table.columns.first.name);

    // A new database arrives with a couple of columns nobody asked for.
    final existing = await FieldBackendService.getFields(viewId: viewId)
        .fold((fields) => fields, (_) => const <FieldPB>[]);
    for (final field in existing) {
      if (field.id != primary.id) {
        await FieldBackendService.deleteField(viewId: viewId, fieldId: field.id);
      }
    }

    // fieldId per column, so a select cell can be written by option id later.
    final fieldIds = <int, String>{0: primary.id};
    final optionIds = <int, Map<String, String>>{};

    for (var index = 1; index < table.columns.length; index++) {
      final column = table.columns[index];
      final options = _optionsFor(column);
      final created = await FieldBackendService.createField(
        viewId: viewId,
        fieldType: column.type,
        fieldName: column.name,
        typeOptionData: _typeOptionFor(column, options),
      ).fold((field) => field, (_) => null);
      if (created == null) {
        Log.warn('[Template] the column "${column.name}" was not added.');
        continue;
      }
      fieldIds[index] = created.id;
      if (options.isNotEmpty) {
        optionIds[index] = {
          for (final option in options) option.name: option.id,
        };
      }
    }

    await _seedRows(
      viewId: viewId,
      table: table,
      fieldIds: fieldIds,
      optionIds: optionIds,
    );
  }

  static List<SelectOptionPB> _optionsFor(TemplateColumn column) => [
        for (final name in column.options)
          SelectOptionPB()
            ..id = nanoid(4)
            ..name = name,
      ];

  static Uint8List? _typeOptionFor(
    TemplateColumn column,
    List<SelectOptionPB> options,
  ) {
    if (options.isEmpty) {
      return null;
    }
    return switch (column.type) {
      FieldType.SingleSelect =>
        (SingleSelectTypeOptionPB()..options.addAll(options)).writeToBuffer(),
      FieldType.MultiSelect =>
        (MultiSelectTypeOptionPB()..options.addAll(options)).writeToBuffer(),
      _ => null,
    };
  }

  static Future<void> _seedRows({
    required String viewId,
    required TemplateTable table,
    required Map<int, String> fieldIds,
    required Map<int, Map<String, String>> optionIds,
  }) async {
    if (table.rows.isEmpty) {
      return;
    }

    // A new database opens with three blank rows; fill those before making
    // more, or the example sits below three empty lines.
    final blanks = await _rowIds(viewId);
    final written = <String>{};

    for (var index = 0; index < table.rows.length; index++) {
      final rowId = index < blanks.length
          ? blanks[index]
          : await RowBackendService.createRow(viewId: viewId)
              .fold((meta) => meta.id, (_) => null);
      if (rowId == null) {
        continue;
      }
      written.add(rowId);
      await _writeRow(
        viewId: viewId,
        rowId: rowId,
        values: table.rows[index],
        columns: table.columns,
        fieldIds: fieldIds,
        optionIds: optionIds,
      );
    }

    // Read again rather than trusting the first read: a database that has
    // never been opened can answer with nothing, and blank rows left under an
    // example read as missing data.
    final surplus = [
      for (final rowId in await _rowIds(viewId))
        if (!written.contains(rowId)) rowId,
    ];
    if (surplus.isNotEmpty) {
      await RowBackendService.deleteRows(viewId, surplus);
    }
  }

  static Future<List<String>> _rowIds(String viewId) =>
      DatabaseEventGetAllRows(DatabaseViewIdPB()..value = viewId)
          .send()
          .fold<List<String>>(
            (all) => [for (final meta in all.items) meta.id],
            (_) => const [],
          );

  static Future<void> _writeRow({
    required String viewId,
    required String rowId,
    required List<String> values,
    required List<TemplateColumn> columns,
    required Map<int, String> fieldIds,
    required Map<int, Map<String, String>> optionIds,
  }) async {
    for (var index = 0; index < values.length && index < columns.length; index++) {
      final value = values[index].trim();
      final fieldId = fieldIds[index];
      if (value.isEmpty || fieldId == null) {
        continue;
      }
      await _writeCell(
        viewId: viewId,
        rowId: rowId,
        fieldId: fieldId,
        column: columns[index],
        options: optionIds[index] ?? const {},
        value: value,
      );
    }
  }

  static Future<void> _writeCell({
    required String viewId,
    required String rowId,
    required String fieldId,
    required TemplateColumn column,
    required Map<String, String> options,
    required String value,
  }) async {
    switch (column.type) {
      case FieldType.SingleSelect:
      case FieldType.MultiSelect:
        final chosen = [
          for (final name in value.split(','))
            if (options[name.trim()] != null) options[name.trim()]!,
        ];
        if (chosen.isNotEmpty) {
          await SelectOptionCellBackendService(
            viewId: viewId,
            fieldId: fieldId,
            rowId: rowId,
          ).select(optionIds: chosen);
        }

      case FieldType.DateTime:
        final date = DateTime.tryParse(value);
        if (date != null) {
          await DateCellBackendService(
            viewId: viewId,
            fieldId: fieldId,
            rowId: rowId,
          ).update(date: date);
        }

      default:
        await CellBackendService.updateCell(
          viewId: viewId,
          cellContext: CellContext(fieldId: fieldId, rowId: rowId),
          data: value,
        );
    }
  }
}
