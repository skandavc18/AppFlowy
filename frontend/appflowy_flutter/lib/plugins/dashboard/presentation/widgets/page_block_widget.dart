import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/document/presentation/embedded_blocks/embedded_blocks_view.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The widget that carries blocks taken from a page's `/` menu.
const dashboardPageBlockType = 'page_block';

/// Where a page block widget keeps its blocks: a document's JSON.
const dashboardPageBlockDocumentKey = 'document';

/// The `/` entry the blocks came from, kept to name the widget.
const dashboardPageBlockNameKey = 'block';

/// Anything from a page's `/` menu, on a dashboard.
///
/// A dashboard offers every block a page can hold — a diagram, a table, a
/// map, an extension's island — and this one widget carries whichever was
/// chosen, rendered by the page's own block builders. It is never offered by
/// name: the "Add" panel lists the `/` entries themselves.
void registerDashboardPageBlockWidget() {
  DashboardWidgetRegistry.register(_pageBlock);
}

final _pageBlock = DashboardWidgetDefinition(
  type: dashboardPageBlockType,
  label: () => LocaleKeys.dashboard_widget_pageBlock.tr(),
  description: () => LocaleKeys.dashboard_widget_pageBlockHint.tr(),
  icon: Icons.dashboard_customize_rounded,
  group: DashboardWidgetGroup.content,
  offered: false,
  defaultColumnSpan: 6,
  defaultRowSpan: 7,
  minimumColumnSpan: 2,
  minimumRowSpan: 2,
  showsTitleByDefault: false,
  // A block may scroll inside itself; the page keeps the wheel until the
  // card is clicked.
  requiresScrollActivation: true,
  padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
  keywords: const ['block', 'page block', 'embed', 'slash'],
  builder: (context) {
    final stored = context.spec.settings[dashboardPageBlockDocumentKey];
    if (stored is! Map) {
      return DashboardPlaceholder(
        palette: context.palette,
        icon: Icons.dashboard_customize_rounded,
        message: LocaleKeys.dashboard_widget_pageBlockEmpty.tr(),
      );
    }
    return EmbeddedBlocksView(
      key: ValueKey('dashboard-page-block-${context.spec.id}'),
      // The same map while nothing changed, so a rebuild is not mistaken
      // for a new document.
      document: stored is Map<String, Object?>
          ? stored
          : Map<String, Object?>.from(stored),
      editable: context.isTypable,
      hostViewId: context.controller.viewId,
      onChanged: (document) =>
          context.setSettings({dashboardPageBlockDocumentKey: document}),
    );
  },
);
