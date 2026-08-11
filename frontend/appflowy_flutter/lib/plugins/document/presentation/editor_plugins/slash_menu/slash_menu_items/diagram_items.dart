import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/drawing/drawing_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/math_equation/math_equation_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mermaid/mermaid_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mind_map/mind_map_block_component.dart';
import 'package:appflowy/shared/mind_map/mind_map.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'slash_menu_item_builder.dart';

/// `/mermaid`
SelectionMenuItem mermaidSlashMenuItem = SelectionMenuItem.node(
  getName: () => LocaleKeys.diagrams_mermaid_name.tr(),
  keywords: const [
    'mermaid',
    'diagram',
    'flowchart',
    'sequence diagram',
    'class diagram',
    'state diagram',
    'entity relationship',
    'gantt',
    'pie chart',
    'graph',
  ],
  nodeBuilder: (editorState, _) => mermaidNode(),
  replace: (_, node) => node.delta?.isEmpty ?? false,
  updateSelection: (editorState, path, __, ___) {
    // Land in the source editor: an empty diagram is not much use on its own.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = editorState.getNodeAtPath(path)?.key.currentState;
      if (state is MermaidBlockComponentState) {
        state.showEditor();
      }
    });
    return null;
  },
  nameBuilder: slashMenuItemNameBuilder,
  iconBuilder: (_, isSelected, style) => SelectableIconWidget(
    icon: Icons.account_tree_rounded,
    isSelected: isSelected,
    style: style,
  ),
);

/// `/mind map`
SelectionMenuItem mindMapSlashMenuItem = SelectionMenuItem.node(
  getName: () => LocaleKeys.diagrams_mindMap_name.tr(),
  keywords: const [
    'mind map',
    'mindmap',
    'brainstorm',
    'ideas',
    'outline',
    'tree',
    'concept map',
  ],
  nodeBuilder: (editorState, _) =>
      mindMapNode(document: MindMapDocument.blank()),
  replace: (_, node) => node.delta?.isEmpty ?? false,
  nameBuilder: slashMenuItemNameBuilder,
  iconBuilder: (_, isSelected, style) => SelectableIconWidget(
    icon: Icons.hub_rounded,
    isSelected: isSelected,
    style: style,
  ),
);

/// `/math`, `/latex`
SelectionMenuItem mathSlashMenuItem = SelectionMenuItem.node(
  getName: () => LocaleKeys.diagrams_math_name.tr(),
  keywords: const [
    'math',
    'maths',
    'latex',
    'tex',
    'katex',
    'equation',
    'formula',
  ],
  nodeBuilder: (editorState, _) => mathEquationNode(),
  replace: (_, node) => node.delta?.isEmpty ?? false,
  updateSelection: (editorState, path, __, ___) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = editorState.getNodeAtPath(path)?.key.currentState;
      if (state is MathEquationBlockComponentWidgetState) {
        state.showEditingDialog();
      }
    });
    return null;
  },
  nameBuilder: slashMenuItemNameBuilder,
  iconBuilder: (_, isSelected, style) => SelectableIconWidget(
    icon: Icons.functions_rounded,
    isSelected: isSelected,
    style: style,
  ),
);

/// `/excalidraw`
SelectionMenuItem excalidrawSlashMenuItem = SelectionMenuItem.node(
  getName: () => LocaleKeys.diagrams_drawing_name.tr(),
  keywords: const [
    'excalidraw',
    'draw',
    'drawing',
    'sketch',
    'whiteboard',
    'freehand',
    'canvas',
  ],
  nodeBuilder: (editorState, _) => drawingNode(),
  replace: (_, node) => node.delta?.isEmpty ?? false,
  updateSelection: (editorState, path, __, ___) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = editorState.getNodeAtPath(path)?.key.currentState;
      if (state is DrawingBlockComponentState) {
        state.openEditor();
      }
    });
    return null;
  },
  nameBuilder: slashMenuItemNameBuilder,
  iconBuilder: (_, isSelected, style) => SelectableIconWidget(
    icon: Icons.draw_rounded,
    isSelected: isSelected,
    style: style,
  ),
);

/// The four blocks that make up the Diagrams & math section.
List<SelectionMenuItem> diagramSlashMenuItems() => [
      mermaidSlashMenuItem,
      mindMapSlashMenuItem,
      mathSlashMenuItem,
      excalidrawSlashMenuItem,
    ];

/// What each of them does, shown as a second line in the menu.
Map<SelectionMenuItem, String> diagramSlashMenuDescriptions() => {
      mermaidSlashMenuItem: LocaleKeys.diagrams_mermaid_description.tr(),
      mindMapSlashMenuItem: LocaleKeys.diagrams_mindMap_description.tr(),
      mathSlashMenuItem: LocaleKeys.diagrams_math_description.tr(),
      excalidrawSlashMenuItem: LocaleKeys.diagrams_drawing_description.tr(),
    };
