import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy/plugins/database/grid/application/row/row_detail_bloc.dart';
import 'package:appflowy/plugins/database/widgets/row/row_document.dart';
import 'package:appflowy/plugins/database_document/database_document_plugin.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_host.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/plugins/document/presentation/editor_drop_manager.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import '../cell/editable_cell_builder.dart';
import 'row_banner.dart';
import 'row_detail_scroll_surface.dart';
import 'row_property.dart';

/// How the row popup is shaped: a landscape 4:3 box, an iPad held sideways.
const double _rowDetailAspectRatio = 4 / 3;
const double _rowDetailMaxWidth = 960;
const double _rowDetailMinHeight = 320;
const double _rowDetailMargin = 56;
const double _rowDetailRadius = 20;

class RowDetailPage extends StatefulWidget with FlowyOverlayDelegate {
  const RowDetailPage({
    super.key,
    required this.rowController,
    required this.databaseController,
    this.allowOpenAsFullPage = true,
    this.userProfile,
  });

  final RowController rowController;
  final DatabaseController databaseController;
  final bool allowOpenAsFullPage;
  final UserProfilePB? userProfile;

  @override
  State<RowDetailPage> createState() => _RowDetailPageState();
}

class _RowDetailPageState extends State<RowDetailPage> {
  // To allow blocking drop target in RowDocument from Field dialogs
  final dropManagerState = EditorDropManagerState();

  late final cellBuilder = EditableCellBuilder(
    databaseController: widget.databaseController,
  );
  final _headerKey = GlobalKey(debugLabel: 'Row detail fields');

  @override
  void dispose() {
    dropManagerState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The dialog adds the view insets to its own margin, so the box has to come
    // off the same total or the content overflows what it was given. It stops
    // short of the window on every side, because the way out is a click on the
    // backdrop.
    final roomWide = media.size.width - _rowDetailMargin * 2;
    final roomTall =
        media.size.height - media.viewInsets.vertical - _rowDetailMargin * 2;

    // The widest 4:3 box the window will take; a short window decides instead.
    double width =
        roomWide.clamp(overlayContainerMinWidth, _rowDetailMaxWidth).toDouble();
    double height = width / _rowDetailAspectRatio;
    final tallest =
        roomTall < _rowDetailMinHeight ? _rowDetailMinHeight : roomTall;
    if (height > tallest) {
      height = tallest;
      width = height * _rowDetailAspectRatio;
    }
    final contentInset = (width * 0.1).clamp(28.0, rowDetailContentInset);

    return FlowyDialog(
      width: width,
      expandHeight: false,
      insetPadding: const EdgeInsets.all(_rowDetailMargin),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_rowDetailRadius),
      ),
      constraints: BoxConstraints.tightFor(height: height),
      padding: EdgeInsets.zero,
      child: ChangeNotifierProvider.value(
        value: dropManagerState,
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => RowDetailBloc(
                fieldController: widget.databaseController.fieldController,
                rowController: widget.rowController,
              ),
            ),
            BlocProvider.value(value: getIt<ReminderBloc>()),
          ],
          child: BlocBuilder<RowDetailBloc, RowDetailState>(
            builder: (context, state) => PageVersionHost(
              viewId: widget.rowController.rowMeta.documentId,
              row: PageVersionRowContext(
                tableViewId: widget.rowController.viewId,
                rowId: widget.rowController.rowId,
              ),
              child: RowDetailScrollSurface(
                coverHeight: rowCoverHeightFor(state.rowMeta),
                actions: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions(context),
                ),
                child: RowDocument(
                  viewId: widget.rowController.viewId,
                  rowId: widget.rowController.rowId,
                  userProfile: widget.userProfile,
                  showComments: true,
                  shrinkWrap: false,
                  contentInset: contentInset,
                  header: KeyedSubtree(
                    key: _headerKey,
                    child: RowDetailHeader(
                      contentInset: contentInset,
                      banner: RowBanner(
                        databaseController: widget.databaseController,
                        rowController: widget.rowController,
                        cellBuilder: cellBuilder,
                        allowOpenAsFullPage: widget.allowOpenAsFullPage,
                        userProfile: widget.userProfile,
                        spacious: true,
                        contentInset: contentInset,
                      ),
                      properties: RowPropertyList(
                        cellBuilder: cellBuilder,
                        viewId: widget.databaseController.viewId,
                        fieldController:
                            widget.databaseController.fieldController,
                        mutedLabels: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> actions(BuildContext context) {
    return [
      if (widget.allowOpenAsFullPage) ...[
        FlowyTooltip(
          message: LocaleKeys.grid_rowPage_openAsFullPage.tr(),
          child: FlowyIconButton(
            width: 20,
            height: 20,
            icon: const FlowySvg(FlowySvgs.full_view_s),
            iconColorOnHover: Theme.of(context).colorScheme.onSurface,
            onPressed: () async {
              Navigator.of(context).pop();
              final databaseId = await DatabaseViewBackendService(
                viewId: widget.databaseController.viewId,
              )
                  .getDatabaseId()
                  .then((value) => value.fold((s) => s, (f) => null));
              final documentId = widget.rowController.rowMeta.documentId;
              if (databaseId != null) {
                getIt<TabsBloc>().add(
                  TabsEvent.openPlugin(
                    plugin: DatabaseDocumentPlugin(
                      data: DatabaseDocumentContext(
                        view: widget.databaseController.view,
                        databaseId: databaseId,
                        rowId: widget.rowController.rowId,
                        documentId: documentId,
                      ),
                      pluginType: PluginType.databaseDocument,
                    ),
                    setLatest: false,
                  ),
                );
              }
            },
          ),
        ),
        const HSpace(4),
      ],
      RowActionButton(rowController: widget.rowController),
    ];
  }
}

/// The popup's page hierarchy. Spacing, rather than rules or nested cards,
/// separates the title, properties and the discussion that follows them.
class RowDetailHeader extends StatelessWidget {
  const RowDetailHeader({
    super.key,
    required this.banner,
    required this.properties,
    this.contentInset = rowDetailContentInset,
  });

  final Widget banner;
  final Widget properties;
  final double contentInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted =
        theme.extension<PremiumThemeExtension>()?.textMuted ?? theme.hintColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        banner,
        const SizedBox(height: 24),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: contentInset),
          child: Semantics(
            header: true,
            child: Text(
              LocaleKeys.grid_settings_properties.tr(),
              key: const ValueKey('row-properties-heading'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                height: 1.4,
                color: muted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          // The drag handle lives in the margin, not ahead of the labels.
          padding: EdgeInsets.only(
            left: contentInset - 24,
            right: contentInset,
          ),
          child: properties,
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
