import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/date_cell_service.dart';
import 'package:appflowy/plugins/database/domain/select_option_cell_service.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail.dart';
import 'package:appflowy/shared/table_views/row_page_text.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Everything a table view needs from the database it is a reading of.
///
/// The grid, the board and the calendar each open their database from their
/// own bloc; these views have none, so this is where they do it — along with
/// opening a row, adding one, and writing an answer back into a cell.
mixin TableViewHostPlumbing<T extends StatefulWidget> on State<T> {
  ViewPB get hostView;

  DatabaseController get hostController;

  TableViewKind get hostKind;

  /// Called when a row changed, so the view can read the table again.
  void onRowsChanged();

  void startHosting() {
    unawaited(_open());
    hostController.rowCache.onRowsChanged((_) => onRowsChanged());
  }

  Future<void> _open() async {
    final result = await hostController.open();
    if (!mounted) {
      return;
    }
    result.fold((_) => onRowsChanged(), Log.error);
  }

  /// Writes this view's own settings back onto the folder.
  void saveHostSettings(Map<String, dynamic> settings) {
    final mark = TableViewMark(kind: hostKind, settings: settings);
    ViewBackendService.updateView(
      viewId: hostView.id,
      extra: mark.mergeIntoExtra(hostView.extra),
    );
  }

  RowMetaPB? metaOf(String rowId) =>
      hostController.rowCache.getRow(rowId)?.rowMeta;

  /// Opens a row the way every other view does.
  ///
  /// A row's own document is only made when its page is first opened, so
  /// sending it straight to a full page asks for a document id that is not
  /// there yet. The page itself carries the button that does that safely.
  void openRow(String rowId) {
    final rowMeta = metaOf(rowId);
    if (rowMeta == null) {
      return;
    }
    openRowMeta(rowMeta);
  }

  void openRowMeta(RowMetaPB rowMeta) {
    unawaited(
      FlowyOverlay.show(
        context: context,
        builder: (_) => BlocProvider.value(
          value: context.read<UserWorkspaceBloc>(),
          child: RowDetailPage(
            rowController: RowController(
              rowMeta: rowMeta,
              viewId: hostController.viewId,
              rowCache: hostController.rowCache,
            ),
            databaseController: hostController,
          ),
        ),
      ).then((_) {
        if (!mounted) {
          return;
        }
        // Whatever was written on the row's page has to be read again, and a
        // page made during the visit had no id to forget.
        RowPageText.forget();
        onRowsChanged();
      }),
    );
  }

  /// Adds a row and opens it, so a new card is never a blank one nobody knows
  /// how to fill in.
  Future<String?> addRow() async {
    final created = await RowBackendService.createRow(viewId: hostView.id);
    if (!mounted) {
      return null;
    }
    return created.fold(
      (rowMeta) {
        onRowsChanged();
        openRowMeta(rowMeta);
        return rowMeta.id;
      },
      (error) {
        Log.error(error);
        return null;
      },
    );
  }

  /// Adds a row already carrying the answers a form collected.
  ///
  /// Text, numbers and dates can be written as the row is made. A choice has
  /// to be picked from the options the column already holds, which is only
  /// possible once the row exists.
  Future<String?> addRowWithAnswers(Map<String, String> answers) async {
    final infos = hostController.fieldController.fieldInfos;
    final byId = {for (final info in infos) info.id: info};

    final created = await RowBackendService.createRow(
      viewId: hostView.id,
      withCells: (builder) {
        for (final entry in answers.entries) {
          final info = byId[entry.key];
          if (info == null || !_writableAtBirth(info)) {
            continue;
          }
          _write(builder, info, entry.value);
        }
      },
    );
    if (!mounted) {
      return null;
    }

    return created.fold(
      (rowMeta) {
        unawaited(_applyChoices(rowMeta.id, answers, byId));
        unawaited(_applyRelations(rowMeta.id, answers, byId));
        onRowsChanged();
        return rowMeta.id;
      },
      (error) {
        Log.error(error);
        return null;
      },
    );
  }

  bool _writableAtBirth(FieldInfo info) => const [
        FieldType.RichText,
        FieldType.URL,
        FieldType.Number,
        FieldType.Checkbox,
        FieldType.DateTime,
        FieldType.Summary,
        FieldType.Translate,
      ].contains(info.fieldType);

  void _write(RowDataBuilder builder, FieldInfo info, String value) {
    switch (info.fieldType) {
      case FieldType.Number:
        final number = int.tryParse(value.replaceAll(',', '').trim());
        if (number != null) {
          builder.insertNumber(info, number);
          return;
        }
        builder.insertText(info, value);
      case FieldType.DateTime:
        final date = parseTableDate(value);
        if (date != null) {
          builder.insertDate(info, date);
          return;
        }
      case FieldType.Checkbox:
        builder.insertText(
          info,
          const ['yes', 'true', '1'].contains(value.trim().toLowerCase())
              ? 'Yes'
              : 'No',
        );
      default:
        builder.insertText(info, value);
    }
  }

  /// Picks the options a form chose, once the row is there to hold them.
  Future<void> _applyChoices(
    String rowId,
    Map<String, String> answers,
    Map<String, FieldInfo> byId,
  ) async {
    for (final entry in answers.entries) {
      final info = byId[entry.key];
      if (info == null) {
        continue;
      }
      if (info.fieldType != FieldType.SingleSelect &&
          info.fieldType != FieldType.MultiSelect) {
        continue;
      }
      final service = SelectOptionCellBackendService(
        viewId: hostController.viewId,
        fieldId: info.id,
        rowId: rowId,
      );
      final wanted = tablePartsOf(entry.value);
      final existing = _optionsOf(info.field);
      final ids = <String>[];
      for (final name in wanted) {
        final match = existing[name.toLowerCase()];
        if (match != null) {
          ids.add(match);
        } else {
          // A choice nobody has made before is worth keeping rather than
          // dropping on the floor.
          await service.create(name: name);
        }
      }
      if (ids.isNotEmpty) {
        await service.select(optionIds: ids);
      }
    }
  }

  /// Points the new row at the rows a form chose.
  ///
  /// A relation names rows rather than holding a value, so the form answers
  /// with their ids and they are linked once the row exists.
  Future<void> _applyRelations(
    String rowId,
    Map<String, String> answers,
    Map<String, FieldInfo> byId,
  ) async {
    for (final entry in answers.entries) {
      final info = byId[entry.key];
      if (info == null || info.fieldType != FieldType.Relation) {
        continue;
      }
      final chosen = tablePartsOf(entry.value);
      if (chosen.isEmpty) {
        continue;
      }
      final payload = RelationCellChangesetPB(
        viewId: hostController.viewId,
        cellId: CellIdPB(
          viewId: hostController.viewId,
          fieldId: info.id,
          rowId: rowId,
        ),
      )..insertedRowIds.addAll(chosen);
      await DatabaseEventUpdateRelationCell(payload).send().fold(
            (_) => null,
            (error) => Log.error(error),
          );
    }
  }

  /// The options a select column already holds, by lowercased name.
  Map<String, String> _optionsOf(FieldPB field) {
    try {
      final parsed = SelectOptionTypeOptionDataParser()
          .fromBuffer(field.typeOptionData)
          .options;
      return {
        for (final option in parsed) option.name.toLowerCase(): option.id,
      };
    } on Object catch (_) {
      return const {};
    }
  }

  /// Moves a row in time, which is what a drag on a timeline means.
  Future<void> rescheduleRow(
    String fieldId,
    String rowId,
    DateTime start,
    DateTime? end,
  ) async {
    if (fieldId.isEmpty) {
      return;
    }
    final service = DateCellBackendService(
      viewId: hostController.viewId,
      fieldId: fieldId,
      rowId: rowId,
    );
    await service.update(
      date: start,
      endDate: end,
      isRange: end != null,
    );
  }
}

/// Reads the options out of a select column's settings.
class SelectOptionTypeOptionDataParser {
  SingleSelectTypeOptionPB fromBuffer(List<int> bytes) =>
      SingleSelectTypeOptionPB.fromBuffer(bytes);
}
