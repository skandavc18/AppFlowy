import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A dashboard widget for every kind of collection the workspace knows about.
///
/// The list is read from [CollectionRegistry] rather than written out here, so
/// a new kind of collection appears in the "Add widget" menu without this file
/// being touched.
void registerDashboardCollectionWidgets() {
  for (final type in CollectionRegistry.types) {
    DashboardWidgetRegistry.register(_definitionFor(type));
  }
}

/// The type part of a collection widget's name, e.g. `collection_book`.
String dashboardCollectionType(CollectionKind kind) =>
    'collection_${kind.name}';

const _keyDisplay = 'display';
const _keyEmbed = 'embed';

/// What the picker offers for a collection widget of [kind].
///
/// A Folder widget also accepts a PLAIN workspace folder or a space: most
/// people never make a folder *collection*, and offering them an empty list is
/// the same as offering nothing. Everything else stays exact — a book shelf
/// cannot draw an album.
bool acceptsDashboardCollection(ViewPB view, CollectionKind kind) {
  if (view.collection?.kind == kind) {
    return true;
  }
  return kind == CollectionKind.folder &&
      view.collection == null &&
      (view.isWorkspaceFolder || view.isSpace);
}

DashboardWidgetDefinition _definitionFor(CollectionTypeDefinition type) =>
    DashboardWidgetDefinition(
      type: dashboardCollectionType(type.kind),
      label: () => type.label,
      description: () => type.description,
      icon: type.icon,
      group: DashboardWidgetGroup.collections,
      defaultColumnSpan: 6,
      defaultRowSpan: 8,
      minimumColumnSpan: 3,
      minimumRowSpan: 4,
      showsTitleByDefault: false,
      // The embed is already a card with its own shadow; a card around a card
      // reads as a double border.
      paintsOwnSurface: true,
      slashName: type.kind.name,
      keywords: [
        'collection',
        type.kind.name,
        ...type.searchKeywords,
      ],
      builder: (context) => _CollectionBody(context: context, kind: type.kind),
      configure: (context) => [
        DashboardConfigView(
          label: type.label,
          viewId: context.spec.source.viewId,
          name: context.spec.source.name,
          filter: (view) => acceptsDashboardCollection(view, type.kind),
          onChanged: (viewId, name) => context.setSource(
            context.spec.source.copyWith(
              kind: viewId.isEmpty
                  ? DashboardSourceKind.none
                  : DashboardSourceKind.collection,
              viewId: viewId,
              name: name,
            ),
          ),
        ),
        DashboardConfigChoice(
          label: LocaleKeys.dashboard_config_display.tr(),
          value: context.spec.setting(_keyDisplay, fallback: 'preview'),
          choices: [
            DashboardChoice(
              value: 'preview',
              label: LocaleKeys.dashboard_display_preview.tr(),
            ),
            DashboardChoice(
              value: 'full',
              label: LocaleKeys.dashboard_display_full.tr(),
            ),
          ],
          onChanged: (value) => context.setSettings({_keyDisplay: value}),
        ),
      ],
    );

class _CollectionBody extends StatelessWidget {
  const _CollectionBody({required this.context, required this.kind});

  final DashboardWidgetContext context;
  final CollectionKind kind;

  @override
  Widget build(BuildContext build) {
    final viewId = context.spec.source.viewId;
    final type = CollectionRegistry.typeFor(kind);
    if (viewId.isEmpty) {
      return DashboardPlaceholder(
        palette: context.palette,
        icon: type.icon,
        message: LocaleKeys.dashboard_widget_pickCollection.tr(
          args: [type.label],
        ),
        action: LocaleKeys.dashboard_config_choose.tr(),
        onAction: () => unawaited(
          context.pickSource(
            kind: DashboardSourceKind.collection,
            filter: (view) => acceptsDashboardCollection(view, kind),
          ),
        ),
      );
    }
    final asPreview =
        context.spec.setting(_keyDisplay, fallback: 'preview') != 'full';
    return DashboardViewBuilder(
      viewId: viewId,
      revision: context.refreshToken,
      placeholder: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      builder: (_, view) => asPreview
          // The collection embed a document draws, with the preview this kind
          // registered — a book shelf, an album wall, a repository tree.
          // `fullscreen` only means "the host owns the size", which on a
          // dashboard it does.
          ? CollectionEmbed(
              key: ValueKey('dashboard-collection-embed-${view.id}'),
              collection: view,
              fullscreen: true,
              editable: context.isTypable,
              settings: CollectionEmbedSettings.fromJson(
                context.spec.settings[_keyEmbed],
              ),
              onSettingsChanged: (next) =>
                  context.setSettings({_keyEmbed: next.toJson()}),
              onChangeCollection: () => unawaited(
                context.pickSource(
                  kind: DashboardSourceKind.collection,
                  filter: (candidate) =>
                      acceptsDashboardCollection(candidate, kind),
                ),
              ),
            )
          : CollectionPage(
              key: ValueKey('dashboard-collection-${view.id}'),
              view: view,
              onOpen: (opened) => _open(opened),
            ),
    );
  }

  void _open(ViewPB view) => unawaited(
        context.run(
          DashboardAction(
            kind: DashboardActionKind.openPage,
            target: view.id,
            targetName: view.name,
          ),
        ),
      );
}
