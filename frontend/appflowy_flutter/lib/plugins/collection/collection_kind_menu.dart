import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The affordance that creates a collection, wherever it is offered.
const collectionAddIcon = Icons.auto_awesome_mosaic_rounded;

abstract final class CollectionKindMenuStyle {
  static const width = 288.0;

  static const popoverConstraints = BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: 520,
  );
}

/// Every registered collection type, as menu entries.
List<AppMenuEntry> collectionKindEntries({
  ValueChanged<CollectionKind>? onSelected,
}) =>
    [
      for (final definition in CollectionRegistry.types)
        AppMenuItem(
          label: definition.label,
          subtitle: definition.description,
          icon: definition.icon,
          value: definition.kind,
          onSelected:
              onSelected == null ? null : () => onSelected(definition.kind),
        ),
    ];

/// Shows the collection types anchored at [globalPosition].
Future<CollectionKind?> showCollectionKindMenu({
  required BuildContext context,
  required Offset globalPosition,
}) =>
    showAppMenu<CollectionKind>(
      context: context,
      globalPosition: globalPosition,
      entries: collectionKindEntries(),
      width: CollectionKindMenuStyle.width,
    );

/// The nested "New collection" entry, which reveals every collection type.
class CollectionAddAction extends PopoverActionCell {
  CollectionAddAction({required this.onCreate});

  final ValueChanged<CollectionKind> onCreate;

  @override
  Widget? leftIcon(Color iconColor) => Icon(
        collectionAddIcon,
        color: iconColor,
        size: AppMenuMetrics.iconSize,
      );

  @override
  String get name => LocaleKeys.collections_newCollection.tr();

  @override
  bool get openOnHover => true;

  @override
  BoxConstraints? get popoverConstraints =>
      CollectionKindMenuStyle.popoverConstraints;

  @override
  PopoverActionCellBuilder get builder =>
      (context, parentController, controller) => CollectionKindList(
            onSelected: (kind) {
              controller.close();
              parentController.close();
              onCreate(kind);
            },
          );
}

/// The collection type rows on their own, for a popover that supplies the card.
class CollectionKindList extends StatelessWidget {
  const CollectionKindList({super.key, required this.onSelected});

  final ValueChanged<CollectionKind> onSelected;

  @override
  Widget build(BuildContext context) {
    final entries = normalizeAppMenuEntries(collectionKindEntries());
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            switch (entry) {
              AppMenuSeparator() => const AppMenuSeparatorLine(),
              AppMenuHeader(:final label) => AppMenuSectionLabel(label: label),
              AppMenuCustom(:final builder) => Builder(builder: builder),
              AppMenuItem() => AppMenuRow(
                  label: entry.label,
                  icon: entry.icon,
                  subtitle: entry.subtitle,
                  tracksHover: true,
                  onTap: () => onSelected(entry.value! as CollectionKind),
                ),
            },
        ],
      ),
    );
  }
}
