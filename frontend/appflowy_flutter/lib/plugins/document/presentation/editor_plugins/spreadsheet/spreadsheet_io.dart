import 'dart:convert';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/share/import_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/foundation.dart';

import 'spreadsheet_codec.dart';
import 'spreadsheet_model.dart';

/// Reading a sheet in from disk and writing it back out again.
///
/// Everything returns a [SpreadsheetIoResult] so the caller can show one toast
/// without knowing which format was involved.
class SpreadsheetIoResult {
  const SpreadsheetIoResult.success(this.message, {this.data}) : failed = false;

  const SpreadsheetIoResult.failure(this.message)
      : failed = true,
        data = null;

  /// Nothing happened — the picker was dismissed.
  const SpreadsheetIoResult.cancelled()
      : failed = false,
        message = null,
        data = null;

  final bool failed;
  final String? message;
  final SpreadsheetData? data;

  bool get hasMessage => message != null;
}

const List<String> spreadsheetImportExtensions = [
  'csv',
  'tsv',
  'txt',
  'xlsx',
  'xlsm',
];

const List<String> spreadsheetDelimitedExtensions = ['csv', 'tsv', 'txt'];
const List<String> spreadsheetWorkbookExtensions = ['xlsx', 'xlsm'];

/// Opens a picker and parses the chosen file into a sheet.
Future<SpreadsheetIoResult> importSpreadsheetFromFile({
  bool headerRow = true,
  List<String> extensions = spreadsheetImportExtensions,
}) async {
  final picked = await getIt<FilePickerService>().pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  final path = picked?.files.firstOrNull?.path;
  if (path == null || path.isEmpty) {
    return const SpreadsheetIoResult.cancelled();
  }
  return importSpreadsheetFromPath(path, headerRow: headerRow);
}

@visibleForTesting
Future<SpreadsheetIoResult> importSpreadsheetFromPath(
  String path, {
  bool headerRow = true,
}) async {
  final file = File(path);
  if (!file.existsSync()) {
    return SpreadsheetIoResult.failure(
      LocaleKeys.spreadsheet_data_importFailed.tr(),
    );
  }
  final extension = path.split('.').last.toLowerCase();
  try {
    List<List<String>> rows;
    if (extension == 'xlsx' || extension == 'xlsm') {
      rows = decodeSpreadsheetXlsx(await file.readAsBytes());
    } else {
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      rows = parseMarkdownTable(text) ?? parseDelimitedText(text);
    }
    if (rows.isEmpty) {
      return SpreadsheetIoResult.failure(
        LocaleKeys.spreadsheet_data_importFailed.tr(),
      );
    }
    if (rows.length > SpreadsheetData.maxRows) {
      rows = rows.sublist(0, SpreadsheetData.maxRows);
    }
    final data = SpreadsheetData.fromRows(rows, headerRow: headerRow);
    return SpreadsheetIoResult.success(
      LocaleKeys.spreadsheet_data_importedRows.tr(args: ['${rows.length}']),
      data: data,
    );
  } on FormatException {
    return SpreadsheetIoResult.failure(
      LocaleKeys.spreadsheet_data_importFailed.tr(),
    );
  } on FileSystemException {
    return SpreadsheetIoResult.failure(
      LocaleKeys.spreadsheet_data_importFailed.tr(),
    );
  } on ArgumentError {
    return SpreadsheetIoResult.failure(
      LocaleKeys.spreadsheet_data_importFailed.tr(),
    );
  } on StateError {
    return SpreadsheetIoResult.failure(
      LocaleKeys.spreadsheet_data_importFailed.tr(),
    );
  }
}

/// Writes the sheet to disk as CSV.
Future<SpreadsheetIoResult> exportSpreadsheetAsCsv(
  SpreadsheetData data, {
  String name = 'sheet.csv',
}) async {
  final rows = spreadsheetDisplayRows(data);
  if (rows.isEmpty) {
    return SpreadsheetIoResult.failure(
      LocaleKeys.spreadsheet_data_nothingToExport.tr(),
    );
  }
  final bytes = Uint8List.fromList(utf8.encode(encodeDelimitedText(rows)));
  final saved = await saveMediaBytes(bytes: bytes, name: name);
  return saved
      ? SpreadsheetIoResult.success(
          LocaleKeys.spreadsheet_data_exported.tr(args: [name]),
        )
      : const SpreadsheetIoResult.cancelled();
}

/// Writes the sheet to disk as a real Excel workbook.
Future<SpreadsheetIoResult> exportSpreadsheetAsXlsx(
  SpreadsheetData data, {
  String name = 'sheet.xlsx',
}) async {
  final bytes = encodeSpreadsheetXlsx(data);
  final saved = await saveMediaBytes(bytes: bytes, name: name);
  return saved
      ? SpreadsheetIoResult.success(
          LocaleKeys.spreadsheet_data_exported.tr(args: [name]),
        )
      : const SpreadsheetIoResult.cancelled();
}

/// Promotes the sheet to a standalone `.xlsx` file in the workspace, where it
/// sits beside markdown, PDFs and images and opens in the Office editor.
Future<SpreadsheetIoResult> saveSpreadsheetToWorkspace({
  required SpreadsheetData data,
  required String parentViewId,
  String name = 'Sheet.xlsx',
  WorkspaceItemService service = const WorkspaceItemService(),
}) async {
  if (parentViewId.isEmpty) {
    return SpreadsheetIoResult.failure(
      LocaleKeys.spreadsheet_data_importFailed.tr(),
    );
  }
  final bytes = encodeSpreadsheetXlsx(data);
  final result = await service.createBlankFile(
    parentViewId: parentViewId,
    kind: WorkspaceFileKind.excel,
    name: name,
    content: bytes,
  );
  return result.fold(
    (view) => SpreadsheetIoResult.success(
      LocaleKeys.spreadsheet_data_savedToWorkspace.tr(args: [view.name]),
    ),
    (error) => SpreadsheetIoResult.failure(
      error.msg.isEmpty
          ? LocaleKeys.spreadsheet_data_importFailed.tr()
          : error.msg,
    ),
  );
}

/// Turns the sheet into a real AppFlowy database grid.
///
/// The values go through the same CSV importer the sidebar uses, so the grid
/// comes out with proper fields and rows rather than a second bespoke path.
Future<SpreadsheetIoResult> convertSpreadsheetToDatabase({
  required SpreadsheetData data,
  required String parentViewId,
  String name = 'Sheet',
}) async {
  if (parentViewId.isEmpty) {
    return SpreadsheetIoResult.failure(
      LocaleKeys.spreadsheet_data_importFailed.tr(),
    );
  }
  // A grid needs named columns, and the importer reads them off the first row.
  final csvRows = spreadsheetDisplayRows(data, includeHeader: true);
  if (csvRows.isEmpty) {
    return SpreadsheetIoResult.failure(
      LocaleKeys.spreadsheet_data_nothingToExport.tr(),
    );
  }
  final rows = data.showHeader
      ? csvRows
      : [
          [
            for (var column = 0; column < csvRows.first.length; column++)
              CellRef.columnLabel(column),
          ],
          ...csvRows,
        ];

  final result = await ImportBackendService.importPages(parentViewId, [
    ImportItemPayloadPB.create()
      ..name = name
      ..data = utf8.encode(encodeDelimitedText(rows))
      ..viewLayout = ViewLayoutPB.Grid
      ..importType = ImportTypePB.CSV,
  ]);

  return result.fold(
    (views) => SpreadsheetIoResult.success(
      LocaleKeys.spreadsheet_data_convertedToDatabase.tr(
        args: [views.items.firstOrNull?.name ?? name],
      ),
    ),
    (error) => SpreadsheetIoResult.failure(
      error.msg.isEmpty
          ? LocaleKeys.spreadsheet_data_importFailed.tr()
          : error.msg,
    ),
  );
}
