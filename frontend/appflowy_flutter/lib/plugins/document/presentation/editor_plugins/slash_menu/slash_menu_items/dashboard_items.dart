import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_templates.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_service.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'slash_menu_item_builder.dart';

/// `/dashboard`, plus one entry per template.
///
/// A dashboard is a page in its own right, so the slash item creates one under
/// the page being written on and leaves a preview card behind pointing at it —
/// the same shape `/book` and the other collections already have.
List<SelectionMenuItem> dashboardSlashMenuItems(DocumentBloc documentBloc) => [
      _dashboardSlashMenuItem(documentBloc),
      for (final template in dashboardTemplates())
        if (template.id != 'blank')
          _templateSlashMenuItem(documentBloc, template),
    ];

Map<SelectionMenuItem, String> dashboardSlashMenuDescriptions(
  List<SelectionMenuItem> items,
) {
  final templates = [
    for (final template in dashboardTemplates())
      if (template.id != 'blank') template,
  ];
  return {
    if (items.isNotEmpty) items.first: LocaleKeys.dashboard_slash_hint.tr(),
    for (var index = 1; index < items.length; index++)
      if (index - 1 < templates.length)
        items[index]: templates[index - 1].description(),
  };
}

SelectionMenuItem _dashboardSlashMenuItem(DocumentBloc documentBloc) =>
    SelectionMenuItem(
      getName: () => LocaleKeys.dashboard_name.tr(),
      keywords: const [
        'dashboard',
        'board',
        'home',
        'workspace',
        'widgets',
        'panel',
      ],
      handler: (editorState, _, __) async =>
          _createDashboard(editorState, documentBloc),
      nameBuilder: slashMenuItemNameBuilder,
      icon: (_, isSelected, style) => SelectableIconWidget(
        icon: Icons.dashboard_rounded,
        isSelected: isSelected,
        style: style,
      ),
    );

SelectionMenuItem _templateSlashMenuItem(
  DocumentBloc documentBloc,
  DashboardTemplate template,
) =>
    SelectionMenuItem(
      getName: () =>
          LocaleKeys.dashboard_slash_template.tr(args: [template.label()]),
      keywords: ['dashboard', template.id, template.label().toLowerCase()],
      handler: (editorState, _, __) async => _createDashboard(
        editorState,
        documentBloc,
        template: template,
      ),
      nameBuilder: slashMenuItemNameBuilder,
      icon: (_, isSelected, style) => SelectableIconWidget(
        icon: template.icon,
        isSelected: isSelected,
        style: style,
      ),
    );

Future<void> _createDashboard(
  EditorState editorState,
  DocumentBloc documentBloc, {
  DashboardTemplate? template,
}) async {
  // Capture the selection before anything awaits: the picker or the backend
  // round trip can take the editor's caret with it.
  final selection = editorState.selection;
  final view = await DashboardService.create(
    parentViewId: documentBloc.documentId,
    name: template?.label(),
    document: template?.build(),
  );
  if (view == null || selection == null || !selection.isCollapsed) {
    return;
  }
  final path = selection.end.path;
  final currentNode = editorState.getNodeAtPath(path);
  if (currentNode == null) {
    return;
  }

  final block = pagePreviewNode(viewId: view.id);
  final transaction = editorState.transaction;
  final delta = currentNode.delta;
  if (delta != null &&
      delta.isEmpty &&
      currentNode.type == ParagraphBlockKeys.type) {
    transaction
      ..insertNode(path, block)
      ..deleteNode(currentNode);
  } else {
    transaction.insertNode(path.next, block);
  }
  await editorState.apply(transaction);
}
