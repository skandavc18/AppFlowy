import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SearchFilterBar extends StatelessWidget {
  const SearchFilterBar({
    required this.filter,
    required this.spaces,
    required this.onChanged,
    super.key,
  });

  final CommandPaletteFilter filter;
  final List<ViewPB> spaces;
  final ValueChanged<CommandPaletteFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedSpace = _selectedSpace();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _FilterButton(
            key: const ValueKey('command-palette-title-filter'),
            icon: Icons.title,
            label: LocaleKeys.commandPalette_titleOnly.tr(),
            selected: filter.titleOnly,
            onTap: () => onChanged(
              filter.copyWith(titleOnly: !filter.titleOnly),
            ),
          ),
          _FilterMenuButton<bool>(
            key: const ValueKey('command-palette-creator-filter'),
            icon: Icons.person_outline,
            label: filter.createdByMe
                ? '${LocaleKeys.commandPalette_createdBy.tr()}: '
                    '${LocaleKeys.commandPalette_me.tr()}'
                : LocaleKeys.commandPalette_createdBy.tr(),
            selected: filter.createdByMe,
            value: filter.createdByMe,
            options: [
              _FilterOption(
                value: false,
                label: LocaleKeys.commandPalette_anyone.tr(),
              ),
              _FilterOption(
                value: true,
                label: LocaleKeys.commandPalette_me.tr(),
              ),
            ],
            onSelected: (value) => onChanged(
              filter.copyWith(createdByMe: value),
            ),
          ),
          _FilterMenuButton<String?>(
            key: const ValueKey('command-palette-space-filter'),
            icon: Icons.folder_outlined,
            label: selectedSpace == null
                ? LocaleKeys.commandPalette_in.tr()
                : '${LocaleKeys.commandPalette_in.tr()}: '
                    '${selectedSpace.nameOrDefault}',
            selected: selectedSpace != null,
            value: filter.spaceId,
            options: [
              _FilterOption(
                value: null,
                label: LocaleKeys.commandPalette_everywhere.tr(),
              ),
              ...spaces.map(
                (space) => _FilterOption(
                  value: space.id,
                  label: space.nameOrDefault,
                ),
              ),
            ],
            onSelected: (value) => onChanged(
              value == null
                  ? filter.copyWith(clearSpace: true)
                  : filter.copyWith(spaceId: value),
            ),
          ),
          _FilterMenuButton<ViewLayoutPB?>(
            key: const ValueKey('command-palette-page-type-filter'),
            icon: filter.pageType == null
                ? Icons.add
                : _pageTypeIcon(filter.pageType!),
            label: filter.pageType == null
                ? LocaleKeys.commandPalette_filter.tr()
                : _pageTypeLabel(filter.pageType!),
            selected: filter.pageType != null,
            value: filter.pageType,
            options: [
              _FilterOption(
                value: null,
                label: LocaleKeys.commandPalette_allPageTypes.tr(),
              ),
              ...[
                ViewLayoutPB.Document,
                ViewLayoutPB.Grid,
                ViewLayoutPB.Board,
                ViewLayoutPB.Calendar,
                ViewLayoutPB.Chat,
              ].map(
                (layout) => _FilterOption(
                  value: layout,
                  label: _pageTypeLabel(layout),
                  icon: _pageTypeIcon(layout),
                ),
              ),
            ],
            onSelected: (value) => onChanged(
              value == null
                  ? filter.copyWith(clearPageType: true)
                  : filter.copyWith(pageType: value),
            ),
          ),
        ],
      ),
    );
  }

  ViewPB? _selectedSpace() {
    final selectedSpaceId = filter.spaceId;
    if (selectedSpaceId == null) {
      return null;
    }
    for (final space in spaces) {
      if (space.id == selectedSpaceId) {
        return space;
      }
    }
    return null;
  }

  static String _pageTypeLabel(ViewLayoutPB layout) => switch (layout) {
        ViewLayoutPB.Document => LocaleKeys.commandPalette_documents.tr(),
        ViewLayoutPB.Grid => LocaleKeys.commandPalette_grids.tr(),
        ViewLayoutPB.Board => LocaleKeys.commandPalette_boards.tr(),
        ViewLayoutPB.Calendar => LocaleKeys.commandPalette_calendars.tr(),
        ViewLayoutPB.Chat => LocaleKeys.commandPalette_chats.tr(),
        _ => LocaleKeys.commandPalette_allPageTypes.tr(),
      };

  static IconData _pageTypeIcon(ViewLayoutPB layout) => switch (layout) {
        ViewLayoutPB.Grid => Icons.table_chart_outlined,
        ViewLayoutPB.Board => Icons.view_kanban_outlined,
        ViewLayoutPB.Calendar => Icons.calendar_today_outlined,
        ViewLayoutPB.Chat => Icons.chat_bubble_outline,
        _ => Icons.description_outlined,
      };
}

class _FilterOption<T> {
  const _FilterOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

class _FilterMenuButton<T> extends StatefulWidget {
  const _FilterMenuButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.value,
    required this.options,
    required this.onSelected,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final T value;
  final List<_FilterOption<T>> options;
  final ValueChanged<T> onSelected;

  @override
  State<_FilterMenuButton<T>> createState() => _FilterMenuButtonState<T>();
}

class _FilterMenuButtonState<T> extends State<_FilterMenuButton<T>> {
  final controller = AFPopoverController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AFPopover(
      controller: controller,
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(),
      anchor: const AFAnchorAuto(offset: Offset(0, 4)),
      popover: (_) => AFMenu(
        width: 220,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: widget.options.map((option) {
                  final selected = option.value == widget.value;
                  return AFTextMenuItem(
                    title: option.label,
                    selected: selected,
                    leading: option.icon == null
                        ? null
                        : Icon(option.icon, size: 18),
                    trailing:
                        selected ? const Icon(Icons.check, size: 18) : null,
                    onTap: () {
                      controller.hide();
                      widget.onSelected(option.value);
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
      child: _FilterButton(
        icon: widget.icon,
        label: widget.label,
        selected: widget.selected,
        showChevron: true,
        onTap: controller.toggle,
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showChevron = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return AFBaseButton(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      borderRadius: theme.borderRadius.m,
      borderColor: (_, __, ___, ____) => Colors.transparent,
      backgroundColor: (_, isHovering, __) => selected || isHovering
          ? theme.fillColorScheme.contentHover
          : Colors.transparent,
      builder: (_, __, ___) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: selected
                ? theme.iconColorScheme.primary
                : theme.iconColorScheme.secondary,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyle.caption.standard(
                color: selected
                    ? theme.textColorScheme.primary
                    : theme.textColorScheme.secondary,
              ),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: theme.iconColorScheme.secondary,
            ),
          ],
        ],
      ),
    );
  }
}
