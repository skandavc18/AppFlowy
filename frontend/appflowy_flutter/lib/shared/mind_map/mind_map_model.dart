import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One node of a mind map.
///
/// The whole map is a plain tree of these and is stored on the block as JSON,
/// so it survives a restart, a copy, a page duplication and workspace sync —
/// and every edit is an ordinary document change that undo already knows how
/// to reverse.
@immutable
class MindMapNode {
  const MindMapNode({
    required this.id,
    required this.text,
    this.children = const <MindMapNode>[],
    this.collapsed = false,
    this.colorIndex,
    this.note = '',
  });

  factory MindMapNode.fromJson(Map<String, dynamic> json) => MindMapNode(
        id: json['id'] as String? ?? newMindMapId(),
        text: json['text'] as String? ?? '',
        collapsed: json['collapsed'] as bool? ?? false,
        colorIndex: (json['color'] as num?)?.toInt(),
        note: json['note'] as String? ?? '',
        children: [
          for (final child in (json['children'] as List<dynamic>? ?? const []))
            if (child is Map)
              MindMapNode.fromJson(Map<String, dynamic>.from(child)),
        ],
      );

  final String id;
  final String text;
  final List<MindMapNode> children;

  /// Whether the branch under this node is folded away.
  final bool collapsed;

  /// An index into the map's accent set, or null to follow the node's depth.
  final int? colorIndex;

  /// A longer aside, shown in the inspector rather than on the node.
  final String note;

  bool get hasChildren => children.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        if (collapsed) 'collapsed': true,
        if (colorIndex != null) 'color': colorIndex,
        if (note.isNotEmpty) 'note': note,
        if (children.isNotEmpty)
          'children': [for (final child in children) child.toJson()],
      };

  MindMapNode copyWith({
    String? text,
    List<MindMapNode>? children,
    bool? collapsed,
    int? colorIndex,
    bool clearColor = false,
    String? note,
  }) =>
      MindMapNode(
        id: id,
        text: text ?? this.text,
        children: children ?? this.children,
        collapsed: collapsed ?? this.collapsed,
        colorIndex: clearColor ? null : (colorIndex ?? this.colorIndex),
        note: note ?? this.note,
      );

  /// Every node under and including this one, in reading order.
  Iterable<MindMapNode> get flattened sync* {
    yield this;
    for (final child in children) {
      yield* child.flattened;
    }
  }
}

/// A whole mind map.
@immutable
class MindMapDocument {
  const MindMapDocument({required this.root, this.title = ''});

  factory MindMapDocument.fromJson(Map<String, dynamic> json) =>
      MindMapDocument(
        title: json['title'] as String? ?? '',
        root: json['root'] is Map
            ? MindMapNode.fromJson(
                Map<String, dynamic>.from(json['root'] as Map))
            : MindMapDocument.blank().root,
      );

  /// A new map with a single, named root, so `/mind map` lands on something
  /// rather than an empty canvas.
  factory MindMapDocument.blank({String rootText = 'Main idea'}) =>
      MindMapDocument(
        root: MindMapNode(
          id: newMindMapId(),
          text: rootText,
          children: [
            MindMapNode(id: newMindMapId(), text: 'Idea A'),
            MindMapNode(id: newMindMapId(), text: 'Idea B'),
            MindMapNode(id: newMindMapId(), text: 'Idea C'),
          ],
        ),
      );

  final MindMapNode root;
  final String title;

  int get nodeCount => root.flattened.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        if (title.isNotEmpty) 'title': title,
        'root': root.toJson(),
      };

  MindMapDocument copyWith({MindMapNode? root, String? title}) =>
      MindMapDocument(root: root ?? this.root, title: title ?? this.title);

  MindMapNode? find(String id) {
    for (final node in root.flattened) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  /// The parent of [id], or null when it is the root or absent.
  MindMapNode? parentOf(String id) {
    MindMapNode? found;
    void walk(MindMapNode node) {
      for (final child in node.children) {
        if (child.id == id) {
          found = node;
          return;
        }
        walk(child);
      }
    }

    walk(root);
    return found;
  }

  /// Whether [ancestorId] is at or above [id], which is what stops a branch
  /// being dropped inside itself.
  bool isAncestor(String ancestorId, String id) {
    final ancestor = find(ancestorId);
    if (ancestor == null) {
      return false;
    }
    return ancestor.flattened.any((node) => node.id == id);
  }

  /// Runs [transform] on the node with [id] and rebuilds the tree around it.
  MindMapDocument mapNode(
    String id,
    MindMapNode Function(MindMapNode node) transform,
  ) {
    MindMapNode walk(MindMapNode node) {
      if (node.id == id) {
        return transform(node);
      }
      if (node.children.isEmpty) {
        return node;
      }
      return node.copyWith(children: [for (final c in node.children) walk(c)]);
    }

    return copyWith(root: walk(root));
  }

  MindMapDocument addChild(String parentId, MindMapNode child) => mapNode(
        parentId,
        (node) => node.copyWith(
          children: [...node.children, child],
          collapsed: false,
        ),
      );

  /// Inserts [sibling] straight after [id]. A sibling of the root becomes its
  /// last child instead, because a map has exactly one trunk.
  MindMapDocument addSibling(String id, MindMapNode sibling) {
    final parent = parentOf(id);
    if (parent == null) {
      return addChild(root.id, sibling);
    }
    return mapNode(parent.id, (node) {
      final index = node.children.indexWhere((child) => child.id == id);
      final children = [...node.children];
      children.insert(index < 0 ? children.length : index + 1, sibling);
      return node.copyWith(children: children);
    });
  }

  /// Removes a node and everything under it. The root cannot be removed.
  MindMapDocument remove(String id) {
    if (id == root.id) {
      return this;
    }
    MindMapNode walk(MindMapNode node) => node.copyWith(
          children: [
            for (final child in node.children)
              if (child.id != id) walk(child),
          ],
        );
    return copyWith(root: walk(root));
  }

  /// Re-parents [id] under [newParentId] at [index].
  ///
  /// A move into the branch's own subtree is refused rather than corrupting
  /// the tree.
  MindMapDocument move(String id, String newParentId, {int? index}) {
    if (id == root.id || isAncestor(id, newParentId)) {
      return this;
    }
    final moving = find(id);
    if (moving == null) {
      return this;
    }
    final without = remove(id);
    return without.mapNode(newParentId, (node) {
      final children = [...node.children];
      final at =
          index == null ? children.length : index.clamp(0, children.length);
      children.insert(at, moving);
      return node.copyWith(children: children, collapsed: false);
    });
  }

  /// Moves [id] up or down among its siblings.
  MindMapDocument reorder(String id, int delta) {
    final parent = parentOf(id);
    if (parent == null) {
      return this;
    }
    return mapNode(parent.id, (node) {
      final children = [...node.children];
      final from = children.indexWhere((child) => child.id == id);
      if (from < 0) {
        return node;
      }
      final to = (from + delta).clamp(0, children.length - 1);
      if (to == from) {
        return node;
      }
      final moving = children.removeAt(from);
      children.insert(to, moving);
      return node.copyWith(children: children);
    });
  }

  /// The map written as an indented list, which is what a copy or a plain
  /// text export should read as.
  String toOutline() {
    final buffer = StringBuffer();
    void walk(MindMapNode node, int depth) {
      buffer.writeln('${'  ' * depth}- ${node.text}');
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    walk(root, 0);
    return buffer.toString();
  }

  /// The map written as Mermaid `mindmap` source, so it can be pasted into a
  /// Mermaid block or anywhere else that understands it.
  String toMermaid() {
    final buffer = StringBuffer('mindmap\n');
    void walk(MindMapNode node, int depth) {
      final indent = '  ' * (depth + 1);
      final label = node.text.replaceAll('\n', ' ');
      buffer.writeln(depth == 0 ? '$indent root(($label))' : '$indent$label');
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    walk(root, 0);
    return buffer.toString();
  }
}

/// Builds a map from an indented outline — one bullet or one tab step per
/// level. Used when a list is dropped or pasted onto a mind map.
MindMapDocument mindMapFromOutline(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return MindMapDocument.blank();
  }

  int indentOf(String line) {
    var count = 0;
    for (final unit in line.codeUnits) {
      if (unit == 0x20) {
        count += 1;
      } else if (unit == 0x09) {
        count += 4;
      } else {
        break;
      }
    }
    return count;
  }

  String labelOf(String line) =>
      line.trim().replaceFirst(RegExp(r'^[-*+•]\s*'), '').trim();

  // Built bottom-up with a stack of open levels: a line closes every level
  // indented at least as far as itself before opening its own.
  final stack = <({int indent, String label, List<MindMapNode> children})>[];
  final roots = <MindMapNode>[];

  void close(int downTo) {
    while (stack.isNotEmpty && stack.last.indent >= downTo) {
      final done = stack.removeLast();
      final node = MindMapNode(
        id: newMindMapId(),
        text: done.label,
        children: done.children,
      );
      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.children.add(node);
      }
    }
  }

  for (final line in lines) {
    final indent = indentOf(line);
    close(indent);
    stack
        .add((indent: indent, label: labelOf(line), children: <MindMapNode>[]));
  }
  close(-1);

  if (roots.length == 1) {
    return MindMapDocument(root: roots.first);
  }
  return MindMapDocument(
    root: MindMapNode(
      id: newMindMapId(),
      text: 'Main idea',
      children: roots,
    ),
  );
}

int _idCounter = 0;

/// A short, unique id. Not a UUID on purpose — it is only ever compared
/// within one map and a shorter id keeps the stored JSON small.
String newMindMapId() {
  _idCounter += 1;
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = math.Random().nextInt(0x3FFFFFFF).toRadixString(36);
  return 'n$stamp$salt$_idCounter';
}
