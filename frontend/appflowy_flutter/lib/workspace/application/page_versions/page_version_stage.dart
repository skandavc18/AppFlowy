import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/workspace/application/page_versions/page_version_content.dart';
import 'package:appflowy/workspace/application/settings/share/import_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show Document;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/uuid.dart';

/// Marks a view as somewhere a version is being shown, and nothing else.
///
/// Every staged view is an orphan, so it never reaches the sidebar — but the
/// mark is what lets a copy left behind by a crash be found and swept.
const String pageVersionScratchKey = 'page_version_scratch';

/// A remembered table, rebuilt so the real grid can be opened on it.
///
/// A table is the one shape that cannot be drawn from what was stored: its
/// grid reads from a database, not from a list of strings. So the rows are
/// imported back into a parentless database and the real view is opened on
/// that, and it is thrown away again the moment the preview closes.
///
/// ⚠️ Nothing else is staged. A page, a file and a folder are drawn straight
/// from the snapshot by the widgets that draw the real ones — staging those
/// was a mistake: an orphan view ignores the content it is created with, so a
/// staged page came out empty, and a made-up view sends the app looking for a
/// page that was never there.
class PageVersionStage {
  PageVersionStage._();

  static final PageVersionStage instance = PageVersionStage._();

  final Map<String, _StagedTable> _staged = {};
  final Map<String, Future<ViewPB?>> _pending = {};
  bool _swept = false;

  /// Stages one version's table, or hands back the copy already staged.
  Future<ViewPB?> mount(String versionId, PageVersionPayload payload) {
    final staged = _staged[versionId];
    if (staged != null) {
      staged.holds += 1;
      return Future.value(staged.view);
    }
    final pending = _pending[versionId];
    if (pending != null) {
      return pending;
    }
    final request = _stage(versionId, payload);
    _pending[versionId] = request;
    return request;
  }

  Future<ViewPB?> _stage(String versionId, PageVersionPayload payload) async {
    try {
      if (!_swept) {
        _swept = true;
        await sweep();
      }
      final view = await _import(payload);
      if (view != null) {
        _staged[versionId] = _StagedTable(view);
      }
      return view;
    } finally {
      _pending.removeWhere((staged, _) => staged == versionId);
    }
  }

  /// Lets go of a staged copy, throwing it away once nothing is showing it.
  Future<void> release(String versionId) async {
    final staged = _staged[versionId];
    if (staged == null) {
      return;
    }
    staged.holds -= 1;
    if (staged.holds > 0) {
      return;
    }
    _staged.remove(versionId);
    await _discard(staged.view);
  }

  /// Whether this view is part of a preview rather than the workspace.
  ///
  /// A row page opened inside a staged table has its document made on the fly
  /// by the row itself, so it carries no mark of its own — the table it
  /// belongs to is what gives it away.
  bool isStaged(String viewId) {
    if (viewId.isEmpty) {
      return false;
    }
    return _staged.values.any(
      (page) =>
          page.view.id == viewId ||
          page.view.childViews.any((child) => child.id == viewId),
    );
  }

  Future<ViewPB?> _import(PageVersionPayload payload) async {
    final table = payload.table;
    if (table == null || table.columns.isEmpty) {
      return null;
    }
    final name = payload.settings.name.isEmpty
        ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
        : payload.settings.name;
    // The rows are rebuilt under a parentless holder, so the copy never shows
    // up beside the table it came from.
    final holder = await ViewBackendService.createOrphanView(
      viewId: uuid(),
      layoutType: ViewLayoutPB.Document,
      name: name,
    );
    final parent = holder.fold((view) => view, (error) {
      Log.warn('A remembered table had nowhere to be staged: $error');
      return null;
    });
    if (parent == null) {
      return null;
    }
    final imported = await ImportBackendService.importPages(parent.id, [
      ImportItemPayloadPB.create()
        ..name = name
        ..data = utf8.encode(table.toCsv())
        ..viewLayout = ViewLayoutPB.Grid
        ..importType = ImportTypePB.CSV,
    ]);
    final staged = imported.fold(
      (views) => views.items.firstOrNull,
      (error) {
        Log.warn('A remembered table could not be staged: $error');
        return null;
      },
    );
    if (staged == null) {
      await _discard(parent);
      return null;
    }
    await _retype(staged.id, table);
    await _restoreRowPages(staged.id, parent.id, table);
    await _mark(parent);
    await _mark(staged);
    // The holder is carried along so both are cleared together.
    return staged..childViews.add(parent);
  }

  /// Gives every staged row the page its row had.
  ///
  /// ⚠️ An import makes fresh rows, so their pages start empty — a remembered
  /// row would open on nothing. The pages are written under the freshly made
  /// row's own document id, which is the id its page will be looked up by.
  Future<void> _restoreRowPages(
    String viewId,
    String parentId,
    PageVersionTable table,
  ) async {
    final pages = [
      for (final row in table.rows)
        if (row.document != null) row,
    ];
    if (pages.isEmpty) {
      return;
    }
    final rows = await DatabaseEventGetRowsAsText(
      DatabaseViewIdPB()..value = viewId,
    ).send().fold<RepeatedRowTextPB?>((rows) => rows, (error) {
      Log.warn('A staged table would not list its rows: $error');
      return null;
    });
    if (rows == null) {
      return;
    }
    // The import keeps the order it was given, so the staged rows line up with
    // the stored ones.
    final service = RowBackendService(viewId: viewId);
    var staged = 0;
    for (var index = 0; index < rows.rows.length; index++) {
      if (index >= table.rows.length) {
        break;
      }
      final document = table.rows[index].document;
      if (document == null) {
        continue;
      }
      final meta = await service.getRowMeta(rows.rows[index].rowId).fold(
        (meta) => meta,
        (error) {
          Log.warn('A staged row would not say where its page is: $error');
          return null;
        },
      );
      final documentId = meta?.documentId ?? '';
      if (documentId.isEmpty) {
        continue;
      }
      final data = DocumentDataPBFromTo.fromDocument(
        Document.fromJson(Map<String, dynamic>.from(document)),
      )?.writeToBuffer();
      if (data == null) {
        continue;
      }
      // A parented view honours the content it is made with; an orphan does
      // not, so the page hangs off the holder rather than nothing.
      final result = await ViewBackendService.createView(
        viewId: documentId,
        parentViewId: parentId,
        layoutType: ViewLayoutPB.Document,
        name: LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
        initialDataBytes: data,
      );
      await result.fold(
        (view) async {
          staged += 1;
          await _mark(view);
          Log.info('Row ${rows.rows[index].rowId} page staged as $documentId');
        },
        (error) async =>
            Log.warn('A remembered row page was not staged: $error'),
      );
    }
    Log.info('Staged $staged of ${pages.length} remembered row page(s)');
  }

  /// Puts every column back to the type it was.
  ///
  /// ⚠️ A CSV carries words and nothing else, so an imported table is all text
  /// — a checkbox reads as "Yes", a date as a sentence. Each column kept its
  /// type when the version was taken, and changing a field's type is exactly
  /// what the app does when you change one by hand, values and all.
  ///
  /// ⚠️ Columns line up by POSITION — the CSV was written in column order and
  /// read back in the same order — but the NAMES have to agree before a type
  /// is applied, and the first column is never touched. `getFields` does not
  /// reliably say which field is primary, and the backend refuses to retype
  /// that one anyway ("Can not update primary field's field type"), so aiming
  /// by position alone quietly put the wrong type on the wrong column.
  Future<void> _retype(String viewId, PageVersionTable table) async {
    final fields = await FieldBackendService.getFields(viewId: viewId)
        .fold<List<FieldPB>>((fields) => fields, (error) {
      Log.warn('A staged table would not say what its columns are: $error');
      return const [];
    });
    if (fields.isEmpty) {
      return;
    }
    final primary = await FieldBackendService.getPrimaryField(viewId: viewId)
        .fold<FieldPB?>((field) => field, (_) => null);
    for (var index = 0; index < fields.length; index++) {
      if (index >= table.columns.length) {
        break;
      }
      final field = fields[index];
      final column = table.columns[index];
      final wanted = FieldType.valueOf(column.fieldType);
      if (wanted == null ||
          index == 0 ||
          field.id == primary?.id ||
          field.name != column.name ||
          field.fieldType == wanted ||
          !_convertsFromText(wanted)) {
        continue;
      }
      final result = await FieldBackendService.updateFieldType(
        viewId: viewId,
        fieldId: field.id,
        fieldType: wanted,
      );
      result.onFailure(
        (error) => Log.warn('"${column.name}" kept its text type: $error'),
      );
    }
  }

  /// Whether a column of words can become this without anything else.
  ///
  /// ⚠️ A relation points at another database, a media cell at stored files,
  /// and the computed columns are worked out rather than written — turning
  /// text into any of those leaves a cell with nothing to read, which is what
  /// draws an error in the grid. Those stay as the words they came back as.
  static bool _convertsFromText(FieldType type) => const {
        FieldType.RichText,
        FieldType.Number,
        FieldType.Checkbox,
        FieldType.DateTime,
        FieldType.SingleSelect,
        FieldType.MultiSelect,
        FieldType.URL,
        FieldType.Checklist,
      }.contains(type);

  Future<void> _discard(ViewPB view) async {
    final ids = [
      for (final child in view.childViews) child.id,
      view.id,
    ];
    final result = await ViewBackendService.deleteViews(viewIds: ids);
    result.onFailure(
      (error) => Log.warn('A staged version could not be cleared: $error'),
    );
  }

  Future<void> _mark(ViewPB view) async {
    final values = decodeViewExtra(view.extra)..[pageVersionScratchKey] = true;
    await ViewBackendService.updateView(
      viewId: view.id,
      extra: jsonEncode(values),
    );
  }

  /// Clears anything a previous run left staged.
  static Future<void> sweep() async {
    final result = await const WorkspaceItemService().getAllViews();
    final views = result.fold((views) => views, (error) {
      Log.warn('Staged versions could not be looked for: $error');
      return const <ViewPB>[];
    });
    final stale = [
      for (final view in views)
        if (decodeViewExtra(view.extra)[pageVersionScratchKey] == true) view.id,
    ];
    if (stale.isEmpty) {
      return;
    }
    Log.info('Clearing ${stale.length} staged version(s) left behind');
    await ViewBackendService.deleteViews(viewIds: stale);
  }
}

class _StagedTable {
  _StagedTable(this.view);

  final ViewPB view;
  int holds = 1;
}
