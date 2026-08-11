import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/shared/mind_map/mind_map.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// A Mermaid block leaves the document as a fenced `mermaid` code block, which
/// is what every markdown renderer that understands Mermaid expects.
class MermaidNodeParser extends NodeParser {
  const MermaidNodeParser();

  @override
  String get id => MermaidBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final source = node.attributes[MermaidBlockKeys.source] as String? ?? '';
    return '```mermaid\n${source.trim()}\n```\n';
  }
}

/// A mind map leaves as the indented list it is, so the ideas survive even
/// where the block does not.
class MindMapNodeParser extends NodeParser {
  const MindMapNodeParser();

  @override
  String get id => MindMapBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final stored = node.attributes[MindMapBlockKeys.data] as String? ?? '';
    if (stored.trim().isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map) {
        return MindMapDocument.fromJson(Map<String, dynamic>.from(decoded))
            .toOutline();
      }
    } catch (_) {
      // A map that cannot be read is better skipped than emitted as noise.
    }
    return '';
  }
}

/// A drawing leaves as its own scene inside a fenced block, so a document that
/// is exported and re-imported still carries something editable.
class DrawingNodeParser extends NodeParser {
  const DrawingNodeParser();

  @override
  String get id => DrawingBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final scene = node.attributes[DrawingBlockKeys.scene] as String? ?? '';
    if (scene.trim().isEmpty) {
      return '';
    }
    return '```excalidraw\n${scene.trim()}\n```\n';
  }
}
