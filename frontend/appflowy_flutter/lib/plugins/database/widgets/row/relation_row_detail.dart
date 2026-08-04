import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/row/related_row_detail_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'row_detail.dart';

/// Opens the page of a row that lives in another database.
void showRelatedRowDetailPage(
  BuildContext context, {
  required String databaseId,
  required String rowId,
}) {
  final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
  FlowyOverlay.show(
    context: context,
    builder: (_) => BlocProvider.value(
      value: userWorkspaceBloc,
      child: RelatedRowDetailPage(databaseId: databaseId, rowId: rowId),
    ),
  );
}

/// The name of a linked row. Clicking it opens that row's page.
class RelatedRowLink extends StatelessWidget {
  const RelatedRowLink({
    super.key,
    required this.databaseId,
    required this.row,
  });

  final String? databaseId;
  final RelatedRowDataPB row;

  @override
  Widget build(BuildContext context) {
    final isEmpty = row.name.trim().isEmpty;
    final label = FlowyText(
      isEmpty ? LocaleKeys.grid_row_titlePlaceholder.tr() : row.name,
      color: isEmpty ? Theme.of(context).hintColor : null,
      decoration: TextDecoration.underline,
      overflow: TextOverflow.ellipsis,
    );

    final id = databaseId;
    if (id == null) {
      return label;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showRelatedRowDetailPage(
          context,
          databaseId: id,
          rowId: row.rowId,
        ),
        child: label,
      ),
    );
  }
}

class RelatedRowDetailPage extends StatelessWidget {
  const RelatedRowDetailPage({
    super.key,
    required this.databaseId,
    required this.rowId,
  });

  final String databaseId;
  final String rowId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => RelatedRowDetailPageBloc(
        databaseId: databaseId,
        initialRowId: rowId,
      ),
      child: BlocBuilder<RelatedRowDetailPageBloc, RelatedRowDetailPageState>(
        builder: (_, state) {
          return state.when(
            loading: () => const Center(
              child: SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
            ),
            ready: (databaseController, rowController) {
              return BlocProvider.value(
                value: context.read<UserWorkspaceBloc>(),
                child: RowDetailPage(
                  databaseController: databaseController,
                  rowController: rowController,
                  allowOpenAsFullPage: false,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
