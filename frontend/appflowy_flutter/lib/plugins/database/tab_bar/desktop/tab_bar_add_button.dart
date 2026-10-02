import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/widgets/database_layout_ext.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/setting_entities.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Hosts without page access keep their existing behavior. A provided access
/// state must finish loading before allowing mutations, even when sharing is
/// disabled and [PageAccessLevelState.isEditable] only checks the page lock.
bool databaseViewMutationsAllowed(PageAccessLevelState? access) =>
    access == null || (!access.isLoadingLockStatus && access.isEditable);

/// The views this database can be shown as.
///
/// A chart is a grid the tab bar draws instead of lists, so it belongs in the
/// same menu as the grid, the board and the calendar.
///
/// Deliberately a class rather than an enum: an extension can register a table
/// view of its own, and the menu has to be able to offer one it has never heard
/// of.
@immutable
class DatabaseTabKind {
  const DatabaseTabKind._(
    this.layout, {
    this.charted = false,
    this.mapped = false,
    this.slided = false,
    this.tableView,
  }) : extensionView = null;

  const DatabaseTabKind.forExtension(this.extensionView)
      : layout = DatabaseLayoutPB.Grid,
        charted = false,
        mapped = false,
        slided = false,
        tableView = null;

  static const grid = DatabaseTabKind._(DatabaseLayoutPB.Grid);
  static const board = DatabaseTabKind._(DatabaseLayoutPB.Board);
  static const calendar = DatabaseTabKind._(DatabaseLayoutPB.Calendar);
  static const gallery = DatabaseTabKind._(
    DatabaseLayoutPB.Grid,
    tableView: TableViewKind.gallery,
  );
  static const timeline = DatabaseTabKind._(
    DatabaseLayoutPB.Grid,
    tableView: TableViewKind.timeline,
  );
  static const feed =
      DatabaseTabKind._(DatabaseLayoutPB.Grid, tableView: TableViewKind.feed);
  static const form =
      DatabaseTabKind._(DatabaseLayoutPB.Grid, tableView: TableViewKind.form);
  static const mailbox = DatabaseTabKind._(
    DatabaseLayoutPB.Grid,
    tableView: TableViewKind.mailbox,
  );
  static const list =
      DatabaseTabKind._(DatabaseLayoutPB.Grid, tableView: TableViewKind.list);
  static const chart = DatabaseTabKind._(DatabaseLayoutPB.Grid, charted: true);
  static const map = DatabaseTabKind._(DatabaseLayoutPB.Grid, mapped: true);
  static const slides = DatabaseTabKind._(DatabaseLayoutPB.Grid, slided: true);

  static const builtIns = <DatabaseTabKind>[
    grid,
    board,
    calendar,
    list,
    gallery,
    timeline,
    feed,
    form,
    mailbox,
    chart,
    map,
    slides,
  ];

  /// Read as the menu opens, so a newly enabled extension is offered at once.
  static List<DatabaseTabKind> all() => [
        ...builtIns,
        for (final view in ExtensionTableViewRegistry.all())
          DatabaseTabKind.forExtension(view),
      ];

  final DatabaseLayoutPB layout;

  /// Whether the new tab draws the database rather than listing it.
  final bool charted;

  /// Whether the new tab places the database rather than listing it.
  final bool mapped;

  /// Whether the new tab reads the database one row at a time.
  final bool slided;

  /// Which of the shared table views the new tab is, if it is one.
  final TableViewKind? tableView;

  /// The extension that supplies this tab, if an extension does.
  final ExtensionTableView? extensionView;

  IconData? get glyph {
    final fromExtension = extensionView;
    if (fromExtension != null) {
      return fromExtension.icon;
    }
    if (charted) {
      return Icons.bar_chart_rounded;
    }
    if (mapped) {
      return Icons.map_rounded;
    }
    if (slided) {
      return Icons.view_carousel_rounded;
    }
    final kind = tableView;
    return kind == null ? null : tableViewIcon(kind);
  }

  String get label {
    final fromExtension = extensionView;
    if (fromExtension != null) {
      return fromExtension.name;
    }
    if (charted) {
      return LocaleKeys.charts_chart.tr();
    }
    if (mapped) {
      return LocaleKeys.map_name.tr();
    }
    if (slided) {
      return LocaleKeys.slides_name.tr();
    }
    return switch (tableView) {
      TableViewKind.timeline => LocaleKeys.timeline_name.tr(),
      TableViewKind.feed => LocaleKeys.feed_name.tr(),
      TableViewKind.form => LocaleKeys.form_name.tr(),
      TableViewKind.gallery => LocaleKeys.gallery_name.tr(),
      TableViewKind.mailbox => LocaleKeys.mailbox_name.tr(),
      TableViewKind.list => LocaleKeys.listView_name.tr(),
      null => layout.layoutName,
    };
  }
}

class AddDatabaseViewButton extends StatefulWidget {
  const AddDatabaseViewButton({
    super.key,
    required this.onTap,
    this.enabled = true,
  });

  final Function(DatabaseTabKind) onTap;
  final bool enabled;

  @override
  State<AddDatabaseViewButton> createState() => _AddDatabaseViewButtonState();
}

class _AddDatabaseViewButtonState extends State<AddDatabaseViewButton> {
  final popoverController = PopoverController();
  VoidCallback? _releasePreview;

  bool get _canAdd =>
      mounted &&
      widget.enabled &&
      databaseViewMutationsAllowed(
        context.read<PageAccessLevelBloc?>()?.state,
      );

  void _showPopover() {
    if (_releasePreview != null || !_canAdd) return;
    _releasePreview = PreviewToolbarRegion.hold(context);
    popoverController.show();
  }

  void _release() {
    _releasePreview?.call();
    _releasePreview = null;
  }

  void _closeIfDisabled() {
    if (_releasePreview == null || _canAdd) return;
    // Access notifications and host changes can arrive during layout. The
    // activation callbacks read live access immediately; close after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _canAdd) return;
      popoverController.close();
      _release();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _closeIfDisabled();
  }

  @override
  void didUpdateWidget(AddDatabaseViewButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _closeIfDisabled();
  }

  @override
  void dispose() {
    final release = _releasePreview;
    _releasePreview = null;
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<PageAccessLevelBloc?>();
    final canAdd =
        widget.enabled && databaseViewMutationsAllowed(access?.state);
    return AppFlowyPopover(
      controller: popoverController,
      constraints: BoxConstraints.loose(const Size(200, 400)),
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      triggerActions: PopoverTriggerFlags.none,
      onClose: _release,
      child: SizedBox(
        width: 36,
        height: 38,
        child: IconButton(
          tooltip: LocaleKeys.grid_createView.tr(),
          onPressed: canAdd ? _showPopover : null,
          style: WorkspaceChrome.controlStyle(context).copyWith(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const DSWorkspaceGlyph.named('plus'),
        ),
      ),
      popupBuilder: (BuildContext context) {
        return TabBarAddButtonAction(
          onTap: (action) {
            popoverController.close();
            if (_canAdd) widget.onTap(action);
          },
        );
      },
    );
  }
}

class TabBarAddButtonAction extends StatelessWidget {
  const TabBarAddButtonAction({super.key, required this.onTap});

  final Function(DatabaseTabKind) onTap;

  @override
  Widget build(BuildContext context) {
    final cells = DatabaseTabKind.all().map((kind) {
      return TabBarAddButtonActionCell(
        action: kind,
        onTap: onTap,
      );
    }).toList();

    return ListView.separated(
      shrinkWrap: true,
      itemCount: cells.length,
      itemBuilder: (BuildContext context, int index) => cells[index],
      separatorBuilder: (BuildContext context, int index) =>
          VSpace(GridSize.typeOptionSeparatorHeight),
      padding: const EdgeInsets.symmetric(vertical: 4.0),
    );
  }
}

class TabBarAddButtonActionCell extends StatelessWidget {
  const TabBarAddButtonActionCell({
    super.key,
    required this.action,
    required this.onTap,
  });

  final DatabaseTabKind action;
  final void Function(DatabaseTabKind) onTap;

  @override
  Widget build(BuildContext context) {
    final label = '${LocaleKeys.grid_createView.tr()} ${action.label}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: TextButton(
          style: WorkspaceChrome.controlStyle(context).copyWith(
            alignment: AlignmentDirectional.centerStart,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => onTap(action),
          child: Row(
            children: [
              if (action.glyph != null)
                DSWorkspaceGlyph(action.glyph!, size: 16)
              else
                DSWorkspaceGlyph.svg(action.layout.icon, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child:
                    Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
