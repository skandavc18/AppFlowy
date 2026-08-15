import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:appflowy/workspace/application/canvas/canvas_geometry.dart';
import 'package:appflowy/workspace/application/canvas/canvas_layout.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';

/// Which tool the pointer is holding.
enum CanvasTool {
  select,
  hand,
  connect,
  text,
  frame,
  draw,
  erase,
}

/// The one object that owns a canvas while it is open: the document, what is
/// selected, the undo history and the writing back.
///
/// It is a plain [ChangeNotifier] rather than a bloc because a canvas changes
/// on every pointer move, and a stream of events per frame would be the wrong
/// shape for that.
class CanvasController extends ChangeNotifier {
  CanvasController({
    required this.viewId,
    required CanvasDocument document,
    this.persistDebounce = const Duration(milliseconds: 700),
    this.maxHistory = 80,
  }) : _document = document;

  final String viewId;
  final Duration persistDebounce;
  final int maxHistory;

  CanvasDocument _document;
  CanvasDocument get document => _document;

  final List<CanvasDocument> _undo = <CanvasDocument>[];
  final List<CanvasDocument> _redo = <CanvasDocument>[];

  Timer? _persist;
  bool _writing = false;
  bool _dirty = false;

  Set<String> _selection = <String>{};
  CanvasTool _tool = CanvasTool.select;
  int? _accent;
  String? _editing;

  // ---------------------------------------------------------------------
  // What is being looked at and worked on
  // ---------------------------------------------------------------------

  Set<String> get selection => Set<String>.unmodifiable(_selection);
  bool isSelected(String id) => _selection.contains(id);
  bool get hasSelection => _selection.isNotEmpty;

  CanvasTool get tool => _tool;

  /// The accent a newly drawn stroke or created card takes.
  int? get accent => _accent;

  /// The card whose text is open for typing, if any.
  String? get editing => _editing;

  CanvasSettings get settings => _document.settings;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void setTool(CanvasTool tool) {
    if (_tool == tool) {
      return;
    }
    _tool = tool;
    if (tool != CanvasTool.select) {
      _editing = null;
    }
    notifyListeners();
  }

  void setAccent(int? accent) {
    if (_accent == accent) {
      return;
    }
    _accent = accent;
    notifyListeners();
  }

  void beginEditing(String? id) {
    if (_editing == id) {
      return;
    }
    _editing = id;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  void select(Iterable<String> ids, {bool add = false, bool toggle = false}) {
    final next = add || toggle ? Set<String>.from(_selection) : <String>{};
    for (final id in ids) {
      if (toggle && next.contains(id)) {
        next.remove(id);
      } else {
        next.add(id);
      }
    }
    if (setEquals(next, _selection)) {
      return;
    }
    _selection = next;
    if (_editing != null && !next.contains(_editing)) {
      _editing = null;
    }
    notifyListeners();
  }

  void clearSelection() => select(const <String>[]);

  void selectAll() => select([
        for (final node in _document.nodes) node.id,
        for (final frame in _document.frames) frame.id,
      ]);

  /// Select everything a frame holds, which is what makes a frame useful as a
  /// grouping rather than only as a drawn box.
  void selectInsideFrame(String frameId) => select([
        frameId,
        for (final node in _document.nodesInFrame(frameId)) node.id,
      ]);

  /// The boxes of everything selected, keyed by id.
  Map<String, Rect> selectedRects() => {
        for (final node in _document.nodes)
          if (_selection.contains(node.id)) node.id: node.rect,
        for (final frame in _document.frames)
          if (_selection.contains(frame.id)) frame.id: frame.rect,
      };

  Rect? get selectionBounds {
    final rects = selectedRects();
    return rects.isEmpty ? null : unionOfCanvasRects(rects.values);
  }

  // ---------------------------------------------------------------------
  // The one way the document changes
  // ---------------------------------------------------------------------

  /// Apply a change.
  ///
  /// [transient] is for the frames of a drag: they must be seen, but a hundred
  /// of them must not become a hundred things to undo. Commit the last one
  /// without it, and the whole drag is one step.
  void edit(
    CanvasDocument Function(CanvasDocument document) change, {
    bool transient = false,
  }) {
    final next = change(_document);
    if (next == _document) {
      return;
    }
    if (!transient) {
      _remember();
    }
    _document = next;
    _schedulePersist();
    notifyListeners();
  }

  void replace(CanvasDocument document, {bool remember = true}) {
    if (document == _document) {
      return;
    }
    if (remember) {
      _remember();
    }
    _document = document;
    _selection = {
      for (final id in _selection)
        if (document.nodeById(id) != null || document.frameById(id) != null) id,
    };
    _schedulePersist();
    notifyListeners();
  }

  void _remember() {
    _undo.add(_document);
    if (_undo.length > maxHistory) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  /// Turn a run of transient edits into ONE entry in the history.
  ///
  /// A drag is a hundred changes that must all be seen and must all be undone
  /// together. The frames are applied with `transient: true` so they cost no
  /// history, and this is called once at the end with the document as it was
  /// before the gesture began.
  void commitGesture(CanvasDocument before) {
    if (before == _document) {
      return;
    }
    _undo.add(before);
    if (_undo.length > maxHistory) {
      _undo.removeAt(0);
    }
    _redo.clear();
    _schedulePersist();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) {
      return;
    }
    _redo.add(_document);
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) {
      return;
    }
    _undo.add(_document);
    _restore(_redo.removeLast());
  }

  /// Step to a remembered document while keeping the CURRENT appearance.
  ///
  /// The settings ride in the document because they are part of what a canvas
  /// is, but they are not part of what was drawn — undoing a move must not
  /// also turn the grid back on.
  void _restore(CanvasDocument document) =>
      replace(document.copyWith(settings: _document.settings), remember: false);

  // ---------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------

  /// Put a card down and select it. Returns the id so the caller can open it
  /// for typing straight away, which is what a double click does.
  String addNode(CanvasNode node, {bool selectIt = true, bool editIt = false}) {
    edit((document) => document.withNode(node));
    if (selectIt) {
      select([node.id]);
    }
    if (editIt) {
      beginEditing(node.id);
    }
    return node.id;
  }

  void updateNode(
    String id,
    CanvasNode Function(CanvasNode node) change, {
    bool transient = false,
  }) {
    edit(
      (document) {
        final node = document.nodeById(id);
        return node == null ? document : document.withNode(change(node));
      },
      transient: transient,
    );
  }

  void updateFrame(
    String id,
    CanvasFrame Function(CanvasFrame frame) change, {
    bool transient = false,
  }) {
    edit(
      (document) {
        final frame = document.frameById(id);
        return frame == null ? document : document.withFrame(change(frame));
      },
      transient: transient,
    );
  }

  void updateEdge(String id, CanvasEdge Function(CanvasEdge edge) change) {
    edit((document) {
      final edge = document.edgeById(id);
      return edge == null ? document : document.withEdge(change(edge));
    });
  }

  /// Move everything selected by [delta].
  ///
  /// Moving a frame carries what it holds, because a frame that leaves its
  /// cards behind is not a group.
  void moveSelection(Offset delta, {bool transient = false}) {
    if (_selection.isEmpty || delta == Offset.zero) {
      return;
    }
    edit(
      (document) => _moved(document, _selection, delta),
      transient: transient,
    );
  }

  CanvasDocument _moved(
    CanvasDocument document,
    Set<String> ids,
    Offset delta,
  ) {
    final movedFrames = <String>{};
    for (final id in ids) {
      if (document.frameById(id) != null) {
        movedFrames
          ..add(id)
          ..addAll(document.descendantFrames(id));
      }
    }
    return document.copyWith(
      nodes: [
        for (final node in document.nodes)
          if (node.locked)
            node
          else if (ids.contains(node.id) ||
              (node.frameId != null && movedFrames.contains(node.frameId)))
            node.copyWith(position: node.position + delta)
          else
            node,
      ],
      frames: [
        for (final frame in document.frames)
          if (movedFrames.contains(frame.id))
            frame.copyWith(position: frame.position + delta)
          else
            frame,
      ],
    );
  }

  void deleteSelection() {
    if (_selection.isEmpty) {
      return;
    }
    final ids = _selection;
    _selection = <String>{};
    _editing = null;
    edit((document) => document.without(ids));
  }

  /// Copy everything selected, offset a little so the copy is visible.
  List<String> duplicateSelection({Offset offset = const Offset(28, 28)}) {
    if (_selection.isEmpty) {
      return const <String>[];
    }
    final made = <String>[];
    edit((document) {
      final frameMap = <String, String>{};
      final nodeMap = <String, String>{};
      final frames = <CanvasFrame>[];
      final nodes = <CanvasNode>[];

      for (final frame in document.frames) {
        if (!_selection.contains(frame.id)) {
          continue;
        }
        final id = newCanvasId('f');
        frameMap[frame.id] = id;
        frames.add(
          CanvasFrame(
            id: id,
            position: frame.position + offset,
            size: frame.size,
            title: frame.title,
            description: frame.description,
            color: frame.color,
            collapsed: frame.collapsed,
            parentId: frame.parentId,
          ),
        );
      }
      // A frame's contents come with it, whether or not they were selected.
      final carried = <String>{
        for (final id in frameMap.keys)
          for (final node in document.nodesInFrame(id)) node.id,
      };
      for (final node in document.nodes) {
        if (!_selection.contains(node.id) && !carried.contains(node.id)) {
          continue;
        }
        final id = newCanvasId();
        nodeMap[node.id] = id;
        nodes.add(
          CanvasNode(
            id: id,
            kind: node.kind,
            position: node.position + offset,
            size: node.size,
            title: node.title,
            text: node.text,
            url: node.url,
            reference: node.reference,
            // A card whose frame came too belongs to the copy of that frame,
            // not to the original.
            frameId: frameMap[node.frameId],
            color: node.color,
            locked: node.locked,
            data: node.data,
          ),
        );
      }

      // A connection is copied only when both of its ends were.
      final rekeyed = <CanvasEdge>[
        for (final edge in document.edges)
          if (nodeMap.containsKey(edge.from) && nodeMap.containsKey(edge.to))
            CanvasEdge(
              id: newCanvasId('e'),
              from: nodeMap[edge.from]!,
              to: nodeMap[edge.to]!,
              fromSide: edge.fromSide,
              toSide: edge.toSide,
              label: edge.label,
              color: edge.color,
              style: edge.style,
              startMarker: edge.startMarker,
              endMarker: edge.endMarker,
              relation: edge.relation,
            ),
      ];

      made
        ..addAll(frameMap.values)
        ..addAll(nodeMap.values);
      return document.copyWith(
        nodes: [...document.nodes, ...nodes],
        frames: [...document.frames, ...frames],
        edges: [...document.edges, ...rekeyed],
      );
    });
    if (made.isNotEmpty) {
      select(made);
    }
    return made;
  }

  // ---------------------------------------------------------------------
  // Connections
  // ---------------------------------------------------------------------

  String? connect(String from, String to, {String label = ''}) {
    if (from == to) {
      return null;
    }
    if (_document.nodeById(from) == null || _document.nodeById(to) == null) {
      return null;
    }
    // The same pair joined twice is almost always a slip, so it is refused.
    for (final edge in _document.edges) {
      if (edge.from == from && edge.to == to) {
        return edge.id;
      }
    }
    final edge = CanvasEdge.create(from: from, to: to, label: label);
    edit((document) => document.withEdge(edge));
    return edge.id;
  }

  void deleteEdge(String id) => edit((document) => document.without([id]));

  // ---------------------------------------------------------------------
  // Frames
  // ---------------------------------------------------------------------

  /// Draw a frame around whatever is selected and file those cards under it.
  String? groupSelection({String title = ''}) {
    final rects = selectedRects();
    if (rects.isEmpty) {
      return null;
    }
    final box = unionOfCanvasRects(rects.values).inflate(28);
    final frame = CanvasFrame.create(
      position: Offset(box.left, box.top - 26),
      size: Size(box.width, box.height + 26),
      title: title,
    );
    final ids = _selection;
    edit(
      (document) => document.copyWith(
        frames: [...document.frames, frame],
        nodes: [
          for (final node in document.nodes)
            if (ids.contains(node.id))
              node.copyWith(frameId: frame.id)
            else
              node,
        ],
      ),
    );
    select([frame.id]);
    return frame.id;
  }

  /// Take the selected cards out of whatever frame holds them.
  void ungroupSelection() {
    if (_selection.isEmpty) {
      return;
    }
    final ids = _selection;
    edit((document) {
      final frames = [
        for (final frame in document.frames)
          if (!ids.contains(frame.id)) frame,
      ];
      final gone = {
        for (final frame in document.frames)
          if (ids.contains(frame.id)) frame.id,
      };
      return document.copyWith(
        frames: frames,
        nodes: [
          for (final node in document.nodes)
            if (ids.contains(node.id) || gone.contains(node.frameId))
              node.copyWith(frameId: null)
            else
              node,
        ],
      );
    });
  }

  /// File a card under whichever frame it is sitting inside, or none.
  void adoptFrameForNode(String nodeId) {
    final node = _document.nodeById(nodeId);
    if (node == null) {
      return;
    }
    String? holder;
    var smallest = double.infinity;
    for (final frame in _document.frames) {
      final area = frame.size.width * frame.size.height;
      if (frame.rect.contains(node.center) && area < smallest) {
        smallest = area;
        holder = frame.id;
      }
    }
    if (holder == node.frameId) {
      return;
    }
    updateNode(nodeId, (current) => current.copyWith(frameId: holder));
  }

  // ---------------------------------------------------------------------
  // Arranging
  // ---------------------------------------------------------------------

  void alignSelection(CanvasAlign align) {
    final moved = alignCanvasRects(selectedRects(), align);
    _applyPositions(moved);
  }

  void distributeSelection(CanvasAxis axis) {
    final moved = distributeCanvasRects(selectedRects(), axis);
    _applyPositions(moved);
  }

  void spaceSelection(CanvasAxis axis, {double gap = 32}) {
    final moved = spaceCanvasRects(selectedRects(), axis, gap: gap);
    _applyPositions(moved);
  }

  void autoLayout(CanvasLayoutKind kind) {
    final moved = layOutCanvas(
      _document,
      kind: kind,
      only: _selection.isEmpty ? null : _selection,
    );
    _applyPositions(moved);
  }

  void _applyPositions(Map<String, Offset> positions) {
    if (positions.isEmpty) {
      return;
    }
    edit(
      (document) => document.copyWith(
        nodes: [
          for (final node in document.nodes)
            if (positions[node.id] != null)
              node.copyWith(position: positions[node.id])
            else
              node,
        ],
        frames: [
          for (final frame in document.frames)
            if (positions[frame.id] != null)
              frame.copyWith(position: positions[frame.id])
            else
              frame,
        ],
      ),
    );
  }

  /// Colour everything selected, cards, frames and the connections between
  /// them, so a group can be told apart at a glance.
  void colourSelection(int? colour) {
    if (_selection.isEmpty) {
      return;
    }
    final ids = _selection;
    edit(
      (document) => document.copyWith(
        nodes: [
          for (final node in document.nodes)
            if (ids.contains(node.id)) node.copyWith(color: colour) else node,
        ],
        frames: [
          for (final frame in document.frames)
            if (ids.contains(frame.id))
              frame.copyWith(color: colour)
            else
              frame,
        ],
        edges: [
          for (final edge in document.edges)
            if (ids.contains(edge.from) && ids.contains(edge.to))
              edge.copyWith(color: colour)
            else
              edge,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Drawing
  // ---------------------------------------------------------------------

  void addStroke(CanvasStroke stroke) => edit(
        (document) => document.copyWith(strokes: [...document.strokes, stroke]),
      );

  /// Rub out every stroke the eraser passed through.
  void eraseStrokesNear(Offset point, {double radius = 12}) {
    final kept = <CanvasStroke>[];
    var removed = false;
    for (final stroke in _document.strokes) {
      if (!stroke.bounds.inflate(radius).contains(point)) {
        kept.add(stroke);
        continue;
      }
      var hit = false;
      for (final vertex in stroke.points) {
        if ((vertex - point).distance <= radius + stroke.width) {
          hit = true;
          break;
        }
      }
      if (hit) {
        removed = true;
      } else {
        kept.add(stroke);
      }
    }
    if (removed) {
      edit((document) => document.copyWith(strokes: kept));
    }
  }

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  void updateSettings(CanvasSettings Function(CanvasSettings settings) change) {
    // A setting is not a change to the drawing, so it does not join the undo
    // history — undoing a move should not also turn the grid back on.
    final next = change(_document.settings);
    if (next == _document.settings) {
      return;
    }
    _document = _document.copyWith(settings: next);
    _schedulePersist();
    notifyListeners();
  }

  /// Remember where the canvas was left. Deliberately silent: the viewport
  /// changes on every pan, and repainting the whole surface for it would make
  /// panning cost a rebuild per frame.
  void rememberViewport(CanvasCamera camera) {
    final viewport = CanvasViewport(offset: camera.offset, zoom: camera.zoom);
    if (viewport == _document.settings.viewport) {
      return;
    }
    _document = _document.copyWith(
      settings: _document.settings.copyWith(viewport: viewport),
    );
    _schedulePersist();
  }

  // ---------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------

  /// Adopt what the backend says, but never over the top of unsaved work.
  void adoptFromView(ViewPB view) {
    if (_writing || _dirty || view.id != viewId) {
      return;
    }
    final incoming = view.canvas?.document;
    if (incoming == null || incoming == _document) {
      return;
    }
    _document = incoming;
    notifyListeners();
  }

  void _schedulePersist() {
    _dirty = true;
    _persist?.cancel();
    _persist = Timer(persistDebounce, () {
      _persist = null;
      unawaited(_write());
    });
  }

  /// Write now rather than on the timer — closing, or handing over to another
  /// surface that is about to read the view.
  Future<void> flush() async {
    _persist?.cancel();
    _persist = null;
    if (_dirty) {
      await _write();
    }
  }

  Future<void> _write() async {
    if (viewId.isEmpty) {
      _dirty = false;
      return;
    }
    _writing = true;
    final document = _document;
    try {
      // Re-read first: the view's extra also carries the cover, the icon and
      // whatever else has been marked on it, and a stale copy would erase it.
      final current = await ViewBackendService.getView(viewId);
      final extra = current.fold((view) => view.extra, (_) => '');
      await ViewBackendService.updateView(
        viewId: viewId,
        extra: CanvasMetadata(document: document).mergeIntoExtra(extra),
      );
    } finally {
      _writing = false;
      // Anything changed while the write was in flight is still unsaved.
      _dirty = document != _document;
      if (_dirty) {
        _schedulePersist();
      }
    }
  }

  @override
  void dispose() {
    _persist?.cancel();
    _persist = null;
    if (_dirty) {
      unawaited(_write());
    }
    super.dispose();
  }
}

/// Search a canvas by what is written on it.
///
/// Pure, so "find on this canvas" behaves the same whether it is asked from the
/// standalone page or from an embedded one.
List<CanvasSearchHit> searchCanvas(CanvasDocument document, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return const <CanvasSearchHit>[];
  }
  final hits = <CanvasSearchHit>[];

  void consider(String id, String? label, String? body, CanvasHitKind kind) {
    final title = (label ?? '').trim();
    final text = (body ?? '').trim();
    final inTitle = title.toLowerCase().contains(needle);
    final inBody = text.toLowerCase().contains(needle);
    if (!inTitle && !inBody) {
      return;
    }
    hits.add(
      CanvasSearchHit(
        id: id,
        kind: kind,
        // A title match is what somebody is usually looking for, so it leads.
        label: title.isNotEmpty ? title : _snippet(text, needle),
        snippet: inBody ? _snippet(text, needle) : '',
        rank: inTitle ? 0 : 1,
      ),
    );
  }

  for (final node in document.nodes) {
    consider(
      node.id,
      node.title,
      '${node.text}\n${node.url}',
      CanvasHitKind.node,
    );
  }
  for (final frame in document.frames) {
    consider(frame.id, frame.title, frame.description, CanvasHitKind.frame);
  }
  for (final edge in document.edges) {
    consider(edge.id, edge.label, edge.relation, CanvasHitKind.edge);
  }

  hits.sort((a, b) {
    final rank = a.rank.compareTo(b.rank);
    return rank != 0 ? rank : a.label.compareTo(b.label);
  });
  return hits;
}

String _snippet(String text, String needle, {int around = 32}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) {
    return '';
  }
  final at = flat.toLowerCase().indexOf(needle);
  if (at < 0) {
    return flat.length <= around * 2
        ? flat
        : '${flat.substring(0, around * 2)}…';
  }
  final start = math.max(0, at - around);
  final end = math.min(flat.length, at + needle.length + around);
  return '${start > 0 ? '…' : ''}${flat.substring(start, end)}'
      '${end < flat.length ? '…' : ''}';
}

enum CanvasHitKind { node, frame, edge }

@immutable
class CanvasSearchHit {
  const CanvasSearchHit({
    required this.id,
    required this.kind,
    required this.label,
    this.snippet = '',
    this.rank = 0,
  });

  final String id;
  final CanvasHitKind kind;
  final String label;
  final String snippet;
  final int rank;

  @override
  bool operator ==(Object other) =>
      other is CanvasSearchHit &&
      other.id == id &&
      other.kind == kind &&
      other.label == label &&
      other.snippet == snippet;

  @override
  int get hashCode => Object.hash(id, kind, label, snippet);
}

/// The things worth listing in a canvas outline: its frames, then any card
/// standing on its own. A hundred unnamed text cards are not an outline.
List<CanvasSearchHit> canvasOutline(CanvasDocument document) {
  final entries = <CanvasSearchHit>[];
  final frames = [...document.frames]..sort((a, b) {
      final row = a.position.dy.compareTo(b.position.dy);
      return row != 0 ? row : a.position.dx.compareTo(b.position.dx);
    });
  for (final frame in frames) {
    entries.add(
      CanvasSearchHit(
        id: frame.id,
        kind: CanvasHitKind.frame,
        label: frame.title,
        snippet: frame.description,
      ),
    );
  }
  final loose = [
    for (final node in document.nodes)
      if (node.frameId == null) node,
  ]..sort((a, b) {
      final row = a.position.dy.compareTo(b.position.dy);
      return row != 0 ? row : a.position.dx.compareTo(b.position.dx);
    });
  for (final node in loose) {
    final label = node.title.trim().isNotEmpty
        ? node.title.trim()
        : node.text.trim().split('\n').first.trim();
    if (label.isEmpty) {
      continue;
    }
    entries.add(
      CanvasSearchHit(id: node.id, kind: CanvasHitKind.node, label: label),
    );
  }
  return entries;
}
