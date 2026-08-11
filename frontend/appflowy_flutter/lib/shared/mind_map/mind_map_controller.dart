import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mind_map_layout.dart';
import 'mind_map_model.dart';

/// Owns a mind map while it is being edited.
///
/// It keeps its own undo history so working inside the canvas feels like a
/// real editor, and reports the settled document back to the host on a short
/// debounce so the page's own undo sees whole edits rather than keystrokes.
class MindMapController extends ChangeNotifier {
  MindMapController({
    required MindMapDocument document,
    this.onChanged,
    this.commitDelay = const Duration(milliseconds: 420),
  }) : _document = document;

  MindMapDocument _document;
  final ValueChanged<MindMapDocument>? onChanged;
  final Duration commitDelay;

  final List<MindMapDocument> _undo = <MindMapDocument>[];
  final List<MindMapDocument> _redo = <MindMapDocument>[];
  Timer? _commit;

  String? _selectedId;
  String? _editingId;
  String _editingText = '';
  MindMapLayoutMode _mode = MindMapLayoutMode.balanced;

  MindMapDocument get document => _document;
  String? get selectedId => _selectedId;
  String? get editingId => _editingId;

  /// What is in the field right now, which is not in the document yet.
  ///
  /// The layout sizes the node from this, so a box grows as it is typed into
  /// rather than cropping what does not fit.
  String get editingText => _editingText;

  MindMapLayoutMode get mode => _mode;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  MindMapNode? get selected =>
      _selectedId == null ? null : _document.find(_selectedId!);

  @override
  void dispose() {
    flush();
    _commit?.cancel();
    super.dispose();
  }

  /// Writes the current document out now, rather than waiting for the pause.
  void flush() {
    if (_commit?.isActive ?? false) {
      _commit!.cancel();
      _commit = null;
      onChanged?.call(_document);
    }
  }

  void setMode(MindMapLayoutMode mode) {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
  }

  void select(String? id) {
    if (_selectedId == id) {
      return;
    }
    _selectedId = id;
    if (_editingId != null && _editingId != id) {
      _editingId = null;
    }
    notifyListeners();
  }

  void beginEditing(String id) {
    _selectedId = id;
    _editingId = id;
    _editingText = _document.find(id)?.text ?? '';
    notifyListeners();
  }

  /// Reports what is in the field, so the node can be measured as it grows.
  void reportEditingText(String text) {
    if (_editingText == text) {
      return;
    }
    _editingText = text;
    notifyListeners();
  }

  void endEditing() {
    if (_editingId == null) {
      return;
    }
    _editingId = null;
    _editingText = '';
    notifyListeners();
  }

  /// Replaces the whole document from outside — an undo on the page, a paste,
  /// a fresh block. It clears the internal history, because that history no
  /// longer describes this map.
  void adopt(MindMapDocument document) {
    if (identical(document, _document)) {
      return;
    }
    _commit?.cancel();
    _commit = null;
    _document = document;
    _undo.clear();
    _redo.clear();
    if (_selectedId != null && document.find(_selectedId!) == null) {
      _selectedId = null;
      _editingId = null;
      _editingText = '';
    }
    notifyListeners();
  }

  void _apply(MindMapDocument next, {bool record = true}) {
    if (identical(next, _document)) {
      return;
    }
    if (record) {
      _undo.add(_document);
      if (_undo.length > 80) {
        _undo.removeAt(0);
      }
      _redo.clear();
    }
    _document = next;
    _commit?.cancel();
    _commit = Timer(commitDelay, () {
      _commit = null;
      onChanged?.call(_document);
    });
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) {
      return;
    }
    _redo.add(_document);
    final previous = _undo.removeLast();
    _apply(previous, record: false);
  }

  void redo() {
    if (_redo.isEmpty) {
      return;
    }
    _undo.add(_document);
    final next = _redo.removeLast();
    _apply(next, record: false);
  }

  // -- editing -------------------------------------------------------------

  String addChild(String parentId, {String text = ''}) {
    final child = MindMapNode(id: newMindMapId(), text: text);
    _apply(_document.addChild(parentId, child));
    _selectedId = child.id;
    _editingId = child.id;
    _editingText = text;
    notifyListeners();
    return child.id;
  }

  String addSibling(String id, {String text = ''}) {
    final sibling = MindMapNode(id: newMindMapId(), text: text);
    _apply(_document.addSibling(id, sibling));
    _selectedId = sibling.id;
    _editingId = sibling.id;
    _editingText = text;
    notifyListeners();
    return sibling.id;
  }

  void rename(String id, String text) {
    if (_editingId == id) {
      _editingText = text;
    }
    final node = _document.find(id);
    if (node == null || node.text == text) {
      return;
    }
    _apply(_document.mapNode(id, (node) => node.copyWith(text: text)));
  }

  void remove(String id) {
    if (id == _document.root.id) {
      return;
    }
    final parent = _document.parentOf(id);
    _apply(_document.remove(id));
    _selectedId = parent?.id;
    _editingId = null;
    notifyListeners();
  }

  void toggleCollapsed(String id) {
    final node = _document.find(id);
    if (node == null || node.children.isEmpty) {
      return;
    }
    _apply(
      _document.mapNode(
          id, (node) => node.copyWith(collapsed: !node.collapsed)),
    );
  }

  void setCollapsedEverywhere({required bool collapsed}) {
    MindMapNode walk(MindMapNode node) => node.copyWith(
          collapsed: node.children.isEmpty ? false : collapsed,
          children: [for (final child in node.children) walk(child)],
        );
    _apply(
      _document.copyWith(
        root: _document.root.copyWith(
          collapsed: false,
          children: [for (final child in _document.root.children) walk(child)],
        ),
      ),
    );
  }

  void setColor(String id, int? colorIndex) {
    _apply(
      _document.mapNode(
        id,
        (node) => node.copyWith(
          colorIndex: colorIndex,
          clearColor: colorIndex == null,
        ),
      ),
    );
  }

  void setNote(String id, String note) {
    _apply(_document.mapNode(id, (node) => node.copyWith(note: note)));
  }

  void reorder(String id, int delta) => _apply(_document.reorder(id, delta));

  void move(String id, String newParentId, {int? index}) =>
      _apply(_document.move(id, newParentId, index: index));

  // -- navigation ----------------------------------------------------------

  /// Moves the selection to the node's parent, first child or nearest
  /// sibling, which is what the arrow keys do on the canvas.
  void moveSelection(MindMapDirection direction, MindMapLayout layout) {
    final current = _selectedId;
    if (current == null) {
      select(_document.root.id);
      return;
    }
    final placement = layout.placementFor(current);
    if (placement == null) {
      return;
    }
    final outward = placement.side == MindMapSide.right
        ? MindMapDirection.right
        : MindMapDirection.left;

    switch (direction) {
      case MindMapDirection.up:
      case MindMapDirection.down:
        final siblings = _siblingsOf(current);
        final index = siblings.indexWhere((node) => node.id == current);
        if (index < 0) {
          return;
        }
        final next = index + (direction == MindMapDirection.up ? -1 : 1);
        if (next >= 0 && next < siblings.length) {
          select(siblings[next].id);
        }
      case MindMapDirection.left:
      case MindMapDirection.right:
        if (direction == outward) {
          final node = _document.find(current);
          if (node != null && node.children.isNotEmpty && !node.collapsed) {
            select(node.children.first.id);
          }
        } else {
          final parent = _document.parentOf(current);
          if (parent != null) {
            select(parent.id);
          }
        }
    }
  }

  List<MindMapNode> _siblingsOf(String id) {
    final parent = _document.parentOf(id);
    return parent?.children ?? <MindMapNode>[_document.root];
  }
}

enum MindMapDirection { up, down, left, right }
