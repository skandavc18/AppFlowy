import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/canvas/canvas_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_view_picker.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_service.dart';
import 'package:appflowy/workspace/application/canvas/canvas_templates.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'slash_menu_item_builder.dart';

/// `/canvas` and its templates.
///
/// Both routes the brief asks for are offered: a brand new canvas that belongs
/// to this page, and an existing one embedded by reference. They insert the
/// same block — the difference is only which canvas it points at.
List<SelectionMenuItem> canvasSlashMenuItems(DocumentBloc documentBloc) => [
      _newCanvasItem(documentBloc),
      _embedCanvasItem(),
      for (final template in canvasTemplates())
        if (template.id != 'blank') _templateItem(documentBloc, template),
    ];

Map<SelectionMenuItem, String> canvasSlashMenuDescriptions(
  List<SelectionMenuItem> items,
) {
  final templates = [
    for (final template in canvasTemplates())
      if (template.id != 'blank') template,
  ];
  return {
    if (items.isNotEmpty) items.first: LocaleKeys.canvas_description.tr(),
    if (items.length > 1) items[1]: LocaleKeys.canvas_embed_embedExisting.tr(),
    // The templates follow the two fixed entries, in the same order.
    for (var index = 2; index < items.length; index++)
      if (index - 2 < templates.length)
        items[index]: templates[index - 2].descriptionKey.tr(),
  };
}

SelectionMenuItem _newCanvasItem(DocumentBloc documentBloc) =>
    SelectionMenuItem(
      getName: () => LocaleKeys.canvas_name.tr(),
      keywords: const [
        'canvas',
        'whiteboard',
        'board',
        'infinite',
        'diagram',
        'map',
        'brainstorm',
        'mind map',
      ],
      handler: (editorState, _, __) async => _insertNewCanvas(
        editorState,
        documentBloc,
      ),
      nameBuilder: slashMenuItemNameBuilder,
      icon: (_, isSelected, style) => SelectableIconWidget(
        icon: Icons.dashboard_customize_rounded,
        isSelected: isSelected,
        style: style,
      ),
    );

SelectionMenuItem _embedCanvasItem() => SelectionMenuItem(
      getName: () => LocaleKeys.canvas_embed_embedExisting.tr(),
      keywords: const ['canvas', 'embed', 'link', 'existing'],
      handler: (editorState, _, context) async =>
          _insertExistingCanvas(editorState, context),
      nameBuilder: slashMenuItemNameBuilder,
      icon: (_, isSelected, style) => SelectableIconWidget(
        icon: Icons.link_rounded,
        isSelected: isSelected,
        style: style,
      ),
    );

SelectionMenuItem _templateItem(
  DocumentBloc documentBloc,
  CanvasTemplate template,
) =>
    SelectionMenuItem(
      getName: () =>
          '${LocaleKeys.canvas_name.tr()} · ${template.nameKey.tr()}',
      keywords: [
        'canvas',
        ...template.nameKey.tr().toLowerCase().split(' '),
      ],
      handler: (editorState, _, __) async => _insertNewCanvas(
        editorState,
        documentBloc,
        template: template,
      ),
      nameBuilder: slashMenuItemNameBuilder,
      icon: (_, isSelected, style) => SelectableIconWidget(
        icon: Icons.auto_awesome_mosaic_rounded,
        isSelected: isSelected,
        style: style,
      ),
    );

Future<void> _insertNewCanvas(
  EditorState editorState,
  DocumentBloc documentBloc, {
  CanvasTemplate? template,
}) async {
  // Capture the selection BEFORE anything asynchronous: creating the view can
  // move the focus, and an insert with no selection is silently dropped.
  final selection = editorState.selection;
  if (selection == null) {
    return;
  }
  final view = await CanvasService.create(
    parentViewId: documentBloc.documentId,
    name: template?.nameKey.tr(),
    document: template?.build(),
  );
  if (view == null) {
    return;
  }
  await _insert(editorState, selection, view.id);
}

Future<void> _insertExistingCanvas(
  EditorState editorState,
  BuildContext context,
) async {
  final selection = editorState.selection;
  if (selection == null) {
    return;
  }
  final view = await showInteractiveViewPicker(
    context,
    filter: (candidate) => candidate.isCanvas,
  );
  if (view == null) {
    return;
  }
  await _insert(editorState, selection, view.id);
}

Future<void> _insert(
  EditorState editorState,
  Selection selection,
  String viewId,
) async {
  final node = editorState.getNodeAtPath(selection.end.path);
  if (node == null) {
    return;
  }
  final transaction = editorState.transaction;
  final isEmptyParagraph =
      node.type == ParagraphBlockKeys.type && (node.delta?.isEmpty ?? true);
  if (isEmptyParagraph) {
    transaction.insertNode(node.path, canvasEmbedNode(viewId: viewId));
    transaction.deleteNode(node);
  } else {
    transaction.insertNode(node.path.next, canvasEmbedNode(viewId: viewId));
  }
  transaction.afterSelection = null;
  await editorState.apply(transaction);
}
