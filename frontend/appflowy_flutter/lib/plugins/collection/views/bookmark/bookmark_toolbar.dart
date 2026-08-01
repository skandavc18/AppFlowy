import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_dialogs.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_state.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The chrome every bookmark view sits in: one toolbar, then the view.
class BookmarkScaffold extends StatelessWidget {
  const BookmarkScaffold({
    super.key,
    required this.collection,
    required this.controller,
    required this.theme,
    required this.child,
    this.trailing = const <Widget>[],
    this.showGrouping = false,
    this.showDensity = false,
  });

  final CollectionViewContext collection;
  final BookmarkController controller;
  final BookmarkTheme theme;
  final Widget child;
  final List<Widget> trailing;
  final bool showGrouping;
  final bool showDensity;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BookmarkToolbar(
            collection: collection,
            controller: controller,
            theme: theme,
            trailing: trailing,
            showGrouping: showGrouping,
            showDensity: showDensity,
          ),
          Expanded(child: child),
        ],
      );
}

/// The one row of controls a library is driven from.
class BookmarkToolbar extends StatelessWidget {
  const BookmarkToolbar({
    super.key,
    required this.collection,
    required this.controller,
    required this.theme,
    this.trailing = const <Widget>[],
    this.showGrouping = false,
    this.showDensity = false,
  });

  final CollectionViewContext collection;
  final BookmarkController controller;
  final BookmarkTheme theme;
  final List<Widget> trailing;
  final bool showGrouping;
  final bool showDensity;

  @override
  Widget build(BuildContext context) {
    final stats = controller.stats;
    final settings = controller.settings;
    final filtered = controller.entries.length != stats.total;

    return SizedBox(
      height: BookmarkMetrics.toolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BookmarkMetrics.gutter,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _meta(
                    filtered
                        ? '${controller.entries.length} / ${stats.total}'
                        : _countLabel(stats.total),
                  ),
                  if (stats.unread > 0) ...[
                    _dot(),
                    _meta(
                      LocaleKeys.collections_bookmark_unreadCount
                          .tr(args: ['${stats.unread}']),
                    ),
                  ],
                  if (stats.offline > 0) ...[
                    _dot(),
                    _meta('${stats.offline} offline'),
                  ],
                  if (controller.isWorking) ...[
                    _dot(),
                    SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: theme.accent,
                      ),
                    ),
                    const SizedBox(width: BookmarkMetrics.space1 + 2),
                    _meta(
                      LocaleKeys.collections_bookmark_reading
                          .tr(args: ['${controller.workingCount}']),
                    ),
                  ],
                ],
              ),
            ),
            ...trailing,
            if (trailing.isNotEmpty)
              const SizedBox(width: BookmarkMetrics.space1),
            BookmarkAction(
              icon: Icons.filter_list_rounded,
              tooltip: LocaleKeys.collections_bookmark_filter.tr(),
              theme: theme,
              active: settings.filter != BookmarkFilter.all ||
                  controller.state.activeTags.isNotEmpty ||
                  controller.state.activeSite != null,
              onPressed: () => _showFilters(context),
            ),
            BookmarkAction(
              icon: Icons.swap_vert_rounded,
              tooltip: LocaleKeys.collections_bookmark_sort.tr(),
              theme: theme,
              onPressed: () => _showSorts(context),
            ),
            if (showGrouping)
              BookmarkAction(
                icon: Icons.dashboard_customize_rounded,
                tooltip: LocaleKeys.collections_bookmark_group.tr(),
                theme: theme,
                onPressed: () => _showGroups(context),
              ),
            if (showDensity)
              BookmarkAction(
                icon: Icons.tune_rounded,
                tooltip: LocaleKeys.collections_bookmark_density.tr(),
                theme: theme,
                onPressed: () => _showDensity(context),
              ),
            BookmarkAction(
              icon: Icons.refresh_rounded,
              tooltip: LocaleKeys.collections_bookmark_refreshAll.tr(),
              theme: theme,
              onPressed:
                  controller.entries.isEmpty ? null : controller.refreshAll,
            ),
            const SizedBox(width: BookmarkMetrics.space1),
            BookmarkAction(
              icon: Icons.add_link_rounded,
              tooltip: LocaleKeys.collections_bookmark_addLink.tr(),
              theme: theme,
              label: LocaleKeys.collections_bookmark_addLink.tr(),
              active: true,
              onPressed: () => showAddBookmarkDialog(
                context: context,
                collection: collection,
                controller: controller,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(String text) => Text(text, style: theme.meta);

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: theme.textFaint.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
        ),
      );

  static String _countLabel(int count) => count == 1
      ? LocaleKeys.collections_bookmark_oneLink.tr()
      : LocaleKeys.collections_bookmark_linkCount.tr(args: ['$count']);

  Future<void> _showFilters(BuildContext context) async {
    final state = controller.state;
    final stats = controller.stats;
    await showAppMenuForWidget<void>(
      context: context,
      entries: [
        AppMenuHeader(LocaleKeys.collections_bookmark_filter.tr()),
        for (final filter in BookmarkFilter.values)
          AppMenuItem(
            label: bookmarkFilterLabel(filter),
            icon: _filterIcon(filter),
            selected: controller.settings.filter == filter,
            onSelected: () => controller
                .updateSettings(controller.settings.copyWith(filter: filter)),
          ),
        if (stats.sites.isNotEmpty) ...[
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.collections_bookmark_allSites.tr(),
            icon: Icons.public_rounded,
            submenu: [
              AppMenuItem(
                label: LocaleKeys.collections_bookmark_allSites.tr(),
                selected: state.activeSite == null,
                onSelected: () => controller.setSiteFilter(null),
              ),
              const AppMenuSeparator(),
              for (final site in stats.sites.take(24))
                AppMenuItem(
                  label: site.label,
                  shortcut: '${site.count}',
                  selected: state.activeSite == site.label,
                  onSelected: () => controller.setSiteFilter(
                    state.activeSite == site.label ? null : site.label,
                  ),
                ),
            ],
          ),
        ],
        if (stats.tags.isNotEmpty)
          AppMenuItem(
            label: LocaleKeys.collections_bookmark_allTags.tr(),
            icon: Icons.sell_rounded,
            submenu: [
              for (final tag in stats.tags.take(30))
                AppMenuItem(
                  label: tag.label,
                  shortcut: '${tag.count}',
                  selected: state.activeTags.contains(tag.label),
                  closeOnSelect: false,
                  onSelected: () => controller.toggleTagFilter(tag.label),
                ),
            ],
          ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.collections_bookmark_clearFilters.tr(),
          icon: Icons.filter_alt_off_rounded,
          enabled: controller.settings.filter != BookmarkFilter.all ||
              state.activeTags.isNotEmpty ||
              state.activeSite != null,
          onSelected: controller.clearFilters,
        ),
      ],
    );
  }

  Future<void> _showSorts(BuildContext context) => showAppMenuForWidget<void>(
        context: context,
        entries: [
          AppMenuHeader(LocaleKeys.collections_bookmark_sort.tr()),
          for (final sort in BookmarkSort.values)
            AppMenuItem(
              label: bookmarkSortLabel(sort),
              selected: controller.settings.sort == sort,
              onSelected: () => controller
                  .updateSettings(controller.settings.copyWith(sort: sort)),
            ),
        ],
      );

  Future<void> _showGroups(BuildContext context) => showAppMenuForWidget<void>(
        context: context,
        entries: [
          AppMenuHeader(LocaleKeys.collections_bookmark_group.tr()),
          for (final grouping in BookmarkGrouping.values)
            AppMenuItem(
              label: bookmarkGroupingLabel(grouping),
              selected: controller.settings.grouping == grouping,
              onSelected: () => controller.updateSettings(
                controller.settings.copyWith(grouping: grouping),
              ),
            ),
        ],
      );

  Future<void> _showDensity(BuildContext context) => showAppMenuForWidget<void>(
        context: context,
        entries: [
          AppMenuHeader(LocaleKeys.collections_bookmark_density.tr()),
          for (final density in BookmarkDensity.values)
            AppMenuItem(
              label: bookmarkDensityLabel(density),
              selected: controller.settings.density == density,
              onSelected: () => controller.updateSettings(
                controller.settings.copyWith(density: density),
              ),
            ),
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.collections_bookmark_showDescriptions.tr(),
            icon: controller.settings.showDescriptions
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            closeOnSelect: false,
            onSelected: () => controller.updateSettings(
              controller.settings.copyWith(
                showDescriptions: !controller.settings.showDescriptions,
              ),
            ),
          ),
        ],
      );

  static IconData _filterIcon(BookmarkFilter filter) => switch (filter) {
        BookmarkFilter.all => Icons.all_inclusive_rounded,
        BookmarkFilter.unread => Icons.mark_email_unread_rounded,
        BookmarkFilter.starred => Icons.star_rounded,
        BookmarkFilter.offline => Icons.cloud_done_rounded,
        BookmarkFilter.untagged => Icons.label_off_rounded,
      };
}

String bookmarkFilterLabel(BookmarkFilter filter) => switch (filter) {
      BookmarkFilter.all => LocaleKeys.collections_bookmark_filters_all.tr(),
      BookmarkFilter.unread =>
        LocaleKeys.collections_bookmark_filters_unread.tr(),
      BookmarkFilter.starred =>
        LocaleKeys.collections_bookmark_filters_starred.tr(),
      BookmarkFilter.offline =>
        LocaleKeys.collections_bookmark_filters_offline.tr(),
      BookmarkFilter.untagged =>
        LocaleKeys.collections_bookmark_filters_untagged.tr(),
    };

String bookmarkSortLabel(BookmarkSort sort) => switch (sort) {
      BookmarkSort.recentlyAdded =>
        LocaleKeys.collections_bookmark_sorts_recentlyAdded.tr(),
      BookmarkSort.oldestFirst =>
        LocaleKeys.collections_bookmark_sorts_oldestFirst.tr(),
      BookmarkSort.published =>
        LocaleKeys.collections_bookmark_sorts_published.tr(),
      BookmarkSort.title => LocaleKeys.collections_bookmark_sorts_title.tr(),
      BookmarkSort.site => LocaleKeys.collections_bookmark_sorts_site.tr(),
      BookmarkSort.unreadFirst =>
        LocaleKeys.collections_bookmark_sorts_unreadFirst.tr(),
    };

String bookmarkGroupingLabel(BookmarkGrouping grouping) => switch (grouping) {
      BookmarkGrouping.none => LocaleKeys.collections_bookmark_groups_none.tr(),
      BookmarkGrouping.site => LocaleKeys.collections_bookmark_groups_site.tr(),
      BookmarkGrouping.tag => LocaleKeys.collections_bookmark_groups_tag.tr(),
      BookmarkGrouping.month =>
        LocaleKeys.collections_bookmark_groups_month.tr(),
      BookmarkGrouping.readState =>
        LocaleKeys.collections_bookmark_groups_readState.tr(),
    };

String bookmarkDensityLabel(BookmarkDensity density) => switch (density) {
      BookmarkDensity.compact =>
        LocaleKeys.collections_bookmark_densities_compact.tr(),
      BookmarkDensity.cosy =>
        LocaleKeys.collections_bookmark_densities_cosy.tr(),
      BookmarkDensity.roomy =>
        LocaleKeys.collections_bookmark_densities_roomy.tr(),
    };

/// The filter chips shown above a view when something is narrowing it.
class BookmarkFilterBar extends StatelessWidget {
  const BookmarkFilterBar({
    super.key,
    required this.controller,
    required this.theme,
  });

  final BookmarkController controller;
  final BookmarkTheme theme;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final chips = <Widget>[
      if (controller.settings.filter != BookmarkFilter.all)
        BookmarkChip(
          label: bookmarkFilterLabel(controller.settings.filter),
          theme: theme,
          selected: true,
          onRemove: () => controller.updateSettings(
            controller.settings.copyWith(filter: BookmarkFilter.all),
          ),
        ),
      if (state.activeSite != null)
        BookmarkChip(
          label: state.activeSite!,
          theme: theme,
          icon: Icons.public_rounded,
          selected: true,
          onRemove: () => controller.setSiteFilter(null),
        ),
      for (final tag in state.activeTags)
        BookmarkChip(
          label: tag,
          theme: theme,
          selected: true,
          onRemove: () => controller.toggleTagFilter(tag),
        ),
    ];

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BookmarkMetrics.gutter,
        0,
        BookmarkMetrics.gutter,
        BookmarkMetrics.space2,
      ),
      child: Wrap(
        spacing: BookmarkMetrics.space1 + 2,
        runSpacing: BookmarkMetrics.space1,
        children: chips,
      ),
    );
  }
}
