import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Every option an embedded collection offers, in one list.
///
/// The same entries are behind the "⋯" button and behind a right click, so a
/// widget never has two different sets of options depending on how it is
/// asked — and they are drawn by the application's own menu, so an embed
/// looks like the rest of AppFlowy rather than like a component library.
List<AppMenuEntry> collectionEmbedMenuEntries({
  required CollectionEmbedContext embed,
  VoidCallback? onChangeCollection,
  VoidCallback? onRemove,
  VoidCallback? onRename,
  VoidCallback? onDuplicate,
  VoidCallback? onFavorite,
}) {
  final settings = embed.settings;
  final definition = embed.definition;
  final editable = embed.editable;

  void apply(CollectionEmbedSettings next) => embed.onSettingsChanged(next);

  final appearance = <AppMenuEntry>[
    AppMenuItem(
      label: LocaleKeys.collections_embed_size.tr(),
      icon: Icons.aspect_ratio_rounded,
      submenu: [
        for (final size in CollectionEmbedSize.values)
          AppMenuItem(
            label: _sizeLabel(size),
            icon: _sizeIcon(size),
            selected: settings.size == size,
            onSelected: () => apply(settings.copyWith(size: size)),
          ),
      ],
    ),
    if (definition.styles.length > 1)
      AppMenuItem(
        label: LocaleKeys.collections_embed_preview.tr(),
        icon: Icons.dashboard_customize_rounded,
        submenu: [
          for (final style in definition.styles)
            AppMenuItem(
              label: style.label,
              icon: style.icon,
              selected: embed.style == style.id,
              onSelected: () => apply(settings.copyWith(style: style.id)),
            ),
        ],
      ),
    if (definition.supportsItemLimit)
      AppMenuItem(
        label: LocaleKeys.collections_embed_items.tr(),
        icon: Icons.format_list_numbered_rounded,
        submenu: [
          for (final limit in const [3, 4, 6, 8, 12, 20])
            AppMenuItem(
              label: LocaleKeys.collections_embed_itemsCount.tr(
                args: ['$limit'],
              ),
              selected: settings.itemLimit == limit,
              onSelected: () => apply(settings.copyWith(itemLimit: limit)),
            ),
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.collections_embed_itemsAuto.tr(),
            selected: settings.itemLimit == null,
            onSelected: () => apply(settings.copyWith(clearItemLimit: true)),
          ),
        ],
      ),
    if (definition.styleFor(embed.style).supportsColumns)
      AppMenuItem(
        label: LocaleKeys.collections_embed_perRow.tr(),
        icon: Icons.view_column_rounded,
        submenu: [
          AppMenuItem(
            label: LocaleKeys.collections_embed_perRowAuto.tr(),
            selected: settings.columns == null,
            onSelected: () => apply(settings.copyWith(clearColumns: true)),
          ),
          const AppMenuSeparator(),
          for (final count in const [2, 3, 4, 5, 6])
            AppMenuItem(
              label: LocaleKeys.collections_embed_perRowCount.tr(
                args: ['$count'],
              ),
              selected: settings.columns == count,
              onSelected: () => apply(settings.copyWith(columns: count)),
            ),
        ],
      ),
    AppMenuItem(
      label: LocaleKeys.collections_embed_sort.tr(),
      icon: Icons.sort_rounded,
      submenu: [
        for (final sort in CollectionEmbedSort.values)
          AppMenuItem(
            label: _sortLabel(sort),
            selected: settings.sort == sort,
            onSelected: () => apply(settings.copyWith(sort: sort)),
          ),
      ],
    ),
    AppMenuItem(
      label: LocaleKeys.collections_embed_background.tr(),
      icon: Icons.layers_rounded,
      submenu: [
        for (final background in CollectionEmbedBackground.values)
          AppMenuItem(
            label: _backgroundLabel(background),
            selected: settings.background == background,
            onSelected: () => apply(settings.copyWith(background: background)),
          ),
      ],
    ),
    AppMenuItem(
      label: LocaleKeys.collections_embed_showDetails.tr(),
      icon: settings.showMetadata
          ? Icons.check_box_rounded
          : Icons.check_box_outline_blank_rounded,
      onSelected: () =>
          apply(settings.copyWith(showMetadata: !settings.showMetadata)),
    ),
  ];

  return [
    if (editable) ...[
      ...appearance,
      const AppMenuSeparator(),
    ],
    AppMenuItem(
      label: embed.fullscreen
          ? LocaleKeys.collections_embed_exitFullscreen.tr()
          : LocaleKeys.collections_embed_fullscreen.tr(),
      icon: embed.fullscreen
          ? Icons.fullscreen_exit_rounded
          : Icons.fullscreen_rounded,
      onSelected: embed.onFullscreen,
    ),
    AppMenuItem(
      label: LocaleKeys.collections_embed_openCollection.tr(),
      icon: Icons.open_in_new_rounded,
      onSelected: embed.onOpenCollection,
    ),
    AppMenuItem(
      label: LocaleKeys.collections_embed_refresh.tr(),
      icon: Icons.refresh_rounded,
      onSelected: embed.onRefresh,
    ),
    if (onRename != null || onFavorite != null || onDuplicate != null) ...[
      const AppMenuSeparator(),
      if (onRename != null)
        AppMenuItem(
          label: LocaleKeys.collections_embed_rename.tr(),
          icon: Icons.edit_rounded,
          onSelected: onRename,
        ),
      if (onFavorite != null)
        AppMenuItem(
          label: LocaleKeys.collections_embed_favorite.tr(),
          icon: Icons.star_rounded,
          onSelected: onFavorite,
        ),
      if (onDuplicate != null)
        AppMenuItem(
          label: LocaleKeys.collections_embed_duplicate.tr(),
          icon: Icons.copy_rounded,
          onSelected: onDuplicate,
        ),
    ],
    if (editable && (onChangeCollection != null || onRemove != null)) ...[
      const AppMenuSeparator(),
      if (onChangeCollection != null)
        AppMenuItem(
          label: LocaleKeys.collections_embed_changeCollection.tr(),
          icon: Icons.swap_horiz_rounded,
          onSelected: onChangeCollection,
        ),
      if (onRemove != null)
        AppMenuItem(
          label: LocaleKeys.collections_embed_remove.tr(),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: onRemove,
        ),
    ],
  ];
}

String _sizeLabel(CollectionEmbedSize size) => switch (size) {
      CollectionEmbedSize.compact =>
        LocaleKeys.collections_embed_sizes_compact.tr(),
      CollectionEmbedSize.medium =>
        LocaleKeys.collections_embed_sizes_medium.tr(),
      CollectionEmbedSize.large =>
        LocaleKeys.collections_embed_sizes_large.tr(),
    };

IconData _sizeIcon(CollectionEmbedSize size) => switch (size) {
      CollectionEmbedSize.compact => Icons.crop_16_9_rounded,
      CollectionEmbedSize.medium => Icons.crop_landscape_rounded,
      CollectionEmbedSize.large => Icons.crop_free_rounded,
    };

String _sortLabel(CollectionEmbedSort sort) => switch (sort) {
      CollectionEmbedSort.manual =>
        LocaleKeys.collections_embed_sortManual.tr(),
      CollectionEmbedSort.name => LocaleKeys.collections_embed_sortName.tr(),
      CollectionEmbedSort.newest =>
        LocaleKeys.collections_embed_sortNewest.tr(),
      CollectionEmbedSort.oldest =>
        LocaleKeys.collections_embed_sortOldest.tr(),
    };

String _backgroundLabel(CollectionEmbedBackground background) =>
    switch (background) {
      CollectionEmbedBackground.surface =>
        LocaleKeys.collections_embed_backgroundSurface.tr(),
      CollectionEmbedBackground.flush =>
        LocaleKeys.collections_embed_backgroundFlush.tr(),
      CollectionEmbedBackground.tinted =>
        LocaleKeys.collections_embed_backgroundTinted.tr(),
    };
