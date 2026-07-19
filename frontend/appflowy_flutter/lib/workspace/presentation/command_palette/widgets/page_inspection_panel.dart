import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

import 'page_preview.dart';

class PageInspectionPanel extends StatefulWidget {
  const PageInspectionPanel({
    required this.view,
    required this.cachedViews,
    required this.currentUserId,
    required this.onOpen,
    required this.onClose,
    super.key,
  });

  final ViewPB view;
  final Map<String, ViewPB> cachedViews;
  final Int64? currentUserId;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  State<PageInspectionPanel> createState() => _PageInspectionPanelState();
}

class _PageInspectionPanelState extends State<PageInspectionPanel> {
  late bool isFavorite;
  bool updatingFavorite = false;

  @override
  void initState() {
    super.initState();
    isFavorite = widget.view.isFavorite;
  }

  @override
  void didUpdateWidget(covariant PageInspectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id) {
      isFavorite = widget.view.isFavorite;
      updatingFavorite = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      key: const ValueKey('command-palette-inspection-panel'),
      margin: const EdgeInsets.only(left: 24),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.borderColorScheme.primary),
        ),
      ),
      child: Column(
        children: [
          _buildMetadata(context),
          Expanded(
            child: Center(
              child: PagePreview(
                key: ValueKey(widget.view.id),
                view: widget.view,
                onViewOpened: widget.onOpen,
              ),
            ),
          ),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildMetadata(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final parent = widget.cachedViews[widget.view.parentViewId];
    final creator = widget.currentUserId != null &&
            widget.view.hasCreatedBy() &&
            widget.view.createdBy == widget.currentUserId
        ? LocaleKeys.commandPalette_me.tr()
        : LocaleKeys.commandPalette_anotherMember.tr();
    final editedAt = DateTime.fromMillisecondsSinceEpoch(
      widget.view.lastEdited.toInt() * 1000,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _layoutIcon(widget.view.layout),
                size: 14,
                color: theme.iconColorScheme.secondary,
              ),
              const HSpace(6),
              Expanded(
                child: Text(
                  parent == null
                      ? _layoutLabel(widget.view.layout)
                      : '${parent.name}  /  ${widget.view.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyle.caption.enhanced(
                    color: theme.textColorScheme.secondary,
                  ),
                ),
              ),
            ],
          ),
          const VSpace(6),
          Text(
            '${LocaleKeys.commandPalette_createdBy.tr()} $creator'
            '  ·  ${LocaleKeys.commandPalette_edited.tr()} '
            '${DateFormat.yMMMd(context.locale.toLanguageTag()).format(editedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyle.caption.enhanced(
              color: theme.textColorScheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
      child: Row(
        children: [
          _ActionButton(
            key: const ValueKey('command-palette-open-action'),
            icon: Icons.arrow_forward_rounded,
            label: LocaleKeys.settings_files_open.tr(),
            onTap: widget.onOpen,
          ),
          const Spacer(),
          FlowyTooltip(
            message: LocaleKeys.disclosureAction_openNewTab.tr(),
            child: FlowyIconButton(
              key: const ValueKey('command-palette-open-new-tab-action'),
              width: 32,
              height: 32,
              icon: Icon(
                Icons.open_in_new_rounded,
                size: 17,
                color: theme.iconColorScheme.secondary,
              ),
              onPressed: () {
                getIt<TabsBloc>().openTab(widget.view);
                widget.onClose();
              },
            ),
          ),
          const HSpace(4),
          FlowyTooltip(
            message: isFavorite
                ? LocaleKeys.disclosureAction_unfavorite.tr()
                : LocaleKeys.disclosureAction_favorite.tr(),
            child: FlowyIconButton(
              key: const ValueKey('command-palette-favorite-action'),
              width: 32,
              height: 32,
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                size: 18,
                color: isFavorite
                    ? theme.iconColorScheme.warningThick
                    : theme.iconColorScheme.secondary,
              ),
              onPressed: updatingFavorite ? null : _toggleFavorite,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    setState(() => updatingFavorite = true);
    final result = await ViewBackendService.favorite(viewId: widget.view.id);
    if (!mounted) return;

    result.fold(
      (_) => setState(() {
        isFavorite = !isFavorite;
        updatingFavorite = false;
      }),
      (error) {
        setState(() => updatingFavorite = false);
        showMessageToast(error.toString(), context: context);
      },
    );
  }

  String _layoutLabel(ViewLayoutPB layout) => switch (layout) {
        ViewLayoutPB.Document => LocaleKeys.commandPalette_documents.tr(),
        ViewLayoutPB.Grid => LocaleKeys.commandPalette_grids.tr(),
        ViewLayoutPB.Board => LocaleKeys.commandPalette_boards.tr(),
        ViewLayoutPB.Calendar => LocaleKeys.commandPalette_calendars.tr(),
        ViewLayoutPB.Chat => LocaleKeys.commandPalette_chats.tr(),
        _ => LocaleKeys.commandPalette_allPageTypes.tr(),
      };

  IconData _layoutIcon(ViewLayoutPB layout) => switch (layout) {
        ViewLayoutPB.Grid => Icons.table_chart_outlined,
        ViewLayoutPB.Board => Icons.view_kanban_outlined,
        ViewLayoutPB.Calendar => Icons.calendar_month_outlined,
        ViewLayoutPB.Chat => Icons.chat_bubble_outline_rounded,
        _ => Icons.description_outlined,
      };
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AFOutlinedButton.normal(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      borderRadius: 8,
      onTap: onTap,
      builder: (context, hovering, disabled) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.iconColorScheme.primary),
          const HSpace(5),
          Text(
            label,
            style: theme.textStyle.caption.enhanced(
              color: theme.textColorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
