import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_templates.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy/plugins/templates/presentation/template_card.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_service.dart';
import 'package:appflowy/workspace/application/templates/template_guides.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/template_service.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'slash_menu_item_builder.dart';

/// The boards that bring tables of their own, when their extensions are on.
List<WorkspaceTemplate> _boards() => [
      for (final template in TemplateRegistry.boards())
        if (missingExtensionsFor(template).isEmpty) template,
    ];

/// `/dashboard`, plus one entry per template.
///
/// A dashboard is a page in its own right, so the slash item creates one under
/// the page being written on and leaves a preview card behind pointing at it —
/// the same shape `/book` and the other collections already have.
List<SelectionMenuItem> dashboardSlashMenuItems(DocumentBloc documentBloc) => [
      _dashboardSlashMenuItem(documentBloc),
      for (final template in _boards())
        _boardSlashMenuItem(documentBloc, template),
      for (final template in dashboardTemplates())
        if (template.id != 'blank')
          _templateSlashMenuItem(documentBloc, template),
    ];

Map<SelectionMenuItem, String> dashboardSlashMenuDescriptions(
  List<SelectionMenuItem> items,
) {
  final descriptions = [
    LocaleKeys.dashboard_slash_hint.tr(),
    for (final template in _boards()) template.description(),
    for (final template in dashboardTemplates())
      if (template.id != 'blank') template.description(),
  ];
  return {
    for (var index = 0; index < items.length; index++)
      if (index < descriptions.length) items[index]: descriptions[index],
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

SelectionMenuItem _boardSlashMenuItem(
  DocumentBloc documentBloc,
  WorkspaceTemplate board,
) =>
    SelectionMenuItem(
      getName: () =>
          LocaleKeys.dashboard_slash_template.tr(args: [board.label()]),
      keywords: [
        'dashboard',
        board.id,
        board.label().toLowerCase(),
        ...board.keywords,
      ],
      handler: (editorState, _, __) async => _createDashboard(
        editorState,
        documentBloc,
        board: board,
      ),
      nameBuilder: slashMenuItemNameBuilder,
      icon: (_, isSelected, style) => SelectableIconWidget(
        icon: board.icon,
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
  WorkspaceTemplate? board,
}) async {
  // Capture the selection before anything awaits: the picker or the backend
  // round trip can take the editor's caret with it.
  final selection = editorState.selection;
  final view = await DashboardService.create(
    parentViewId: documentBloc.documentId,
    name: board?.label() ?? template?.label(),
    document: template?.build().copyWith(guide: templateGuide(template.id)),
  );
  if (view != null && board != null) {
    // The board's tables are made beneath it, then the board bound to them.
    await TemplateService.applyTo(view: view, template: board);
  }
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
