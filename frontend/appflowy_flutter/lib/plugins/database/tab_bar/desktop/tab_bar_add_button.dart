import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/widgets/database_layout_ext.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/setting_entities.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/extension.dart';
import 'package:flutter/material.dart';

/// The views this database can be shown as.
///
/// A chart is a grid the tab bar draws instead of lists, so it belongs in the
/// same menu as the grid, the board and the calendar.
enum DatabaseTabKind {
  grid(DatabaseLayoutPB.Grid),
  board(DatabaseLayoutPB.Board),
  calendar(DatabaseLayoutPB.Calendar),
  gallery(DatabaseLayoutPB.Grid, tableView: TableViewKind.gallery),
  timeline(DatabaseLayoutPB.Grid, tableView: TableViewKind.timeline),
  feed(DatabaseLayoutPB.Grid, tableView: TableViewKind.feed),
  form(DatabaseLayoutPB.Grid, tableView: TableViewKind.form),
  mailbox(DatabaseLayoutPB.Grid, tableView: TableViewKind.mailbox),
  chart(DatabaseLayoutPB.Grid, charted: true),
  map(DatabaseLayoutPB.Grid, mapped: true),
  slides(DatabaseLayoutPB.Grid, slided: true);

  const DatabaseTabKind(
    this.layout, {
    this.charted = false,
    this.mapped = false,
    this.slided = false,
    this.tableView,
  });

  final DatabaseLayoutPB layout;

  /// Whether the new tab draws the database rather than listing it.
  final bool charted;

  /// Whether the new tab places the database rather than listing it.
  final bool mapped;

  /// Whether the new tab reads the database one row at a time.
  final bool slided;

  /// Which of the shared table views the new tab is, if it is one.
  final TableViewKind? tableView;

  IconData? get glyph {
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
      null => layout.layoutName,
    };
  }
}

class AddDatabaseViewButton extends StatefulWidget {
  const AddDatabaseViewButton({super.key, required this.onTap});

  final Function(DatabaseTabKind) onTap;

  @override
  State<AddDatabaseViewButton> createState() => _AddDatabaseViewButtonState();
}

class _AddDatabaseViewButtonState extends State<AddDatabaseViewButton> {
  final popoverController = PopoverController();

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      controller: popoverController,
      constraints: BoxConstraints.loose(const Size(200, 400)),
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      triggerActions: PopoverTriggerFlags.none,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          top: 2.0,
          bottom: 7.0,
          start: 6.0,
        ),
        child: FlowyIconButton(
          width: 26,
          hoverColor: AFThemeExtension.of(context).greyHover,
          onPressed: () => popoverController.show(),
          radius: Corners.s4Border,
          icon: FlowySvg(
            FlowySvgs.add_s,
            color: Theme.of(context).hintColor,
          ),
          iconColorOnHover: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      popupBuilder: (BuildContext context) {
        return TabBarAddButtonAction(
          onTap: (action) {
            popoverController.close();
            widget.onTap(action);
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
    final cells = DatabaseTabKind.values.map((kind) {
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
    return SizedBox(
      height: GridSize.popoverItemHeight,
      child: FlowyButton(
        hoverColor: AFThemeExtension.of(context).lightGreyHover,
        text: FlowyText(
          '${LocaleKeys.grid_createView.tr()} ${action.label}',
          color: AFThemeExtension.of(context).textColor,
        ),
        leftIcon: action.glyph != null
            ? Icon(
                action.glyph,
                size: 16,
                color: Theme.of(context).iconTheme.color,
              )
            : FlowySvg(
                action.layout.icon,
                color: Theme.of(context).iconTheme.color,
              ),
        onTap: () => onTap(action),
      ).padding(horizontal: 6.0),
    );
  }
}
