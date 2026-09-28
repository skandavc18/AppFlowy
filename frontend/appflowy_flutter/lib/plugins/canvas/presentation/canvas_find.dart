import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';

typedef CanvasFindId = (CanvasHitKind, String, CanvasSearchField);

CanvasFindId canvasFindNode(String id, CanvasSearchField field) =>
    (CanvasHitKind.node, id, field);
CanvasFindId canvasFindFrame(String id, CanvasSearchField field) =>
    (CanvasHitKind.frame, id, field);

bool _replaceable(CanvasController canvas, CanvasFindId id) {
  final document = canvas.document;
  switch (id.$1) {
    case CanvasHitKind.node:
      final node = document.nodeById(id.$2);
      if (node == null || node.locked || canvas.editing == node.id) {
        return false;
      }
      if (node.kind.referencesWorkspaceObject) return false;
      return id.$3 == CanvasSearchField.title ||
          (id.$3 == CanvasSearchField.text && node.typesItsOwnText);
    case CanvasHitKind.frame:
      return document.frameById(id.$2) != null &&
          (id.$3 == CanvasSearchField.title ||
              id.$3 == CanvasSearchField.description);
    case CanvasHitKind.edge:
      final edge = document.edgeById(id.$2);
      return edge != null &&
          document.nodeById(edge.from)?.locked == false &&
          document.nodeById(edge.to)?.locked == false &&
          (id.$3 == CanvasSearchField.label ||
              id.$3 == CanvasSearchField.relation);
  }
}

class CanvasFindController extends SurfaceFindController {
  CanvasFindController({
    required this.canvas,
    required bool Function() editable,
  }) : super(
          search: (query, options) => [
            for (final hit in searchCanvas(
              canvas.document,
              query,
              options: options,
              occurrences: true,
            ))
              SurfaceFindMatch(
                SurfaceFindEntry(
                  (hit.kind, hit.id, hit.field),
                  hit.source,
                  replaceable: editable() &&
                      _replaceable(canvas, (hit.kind, hit.id, hit.field)),
                ),
                hit.match!,
              ),
          ],
          canReplace: editable,
          applyReplacements: (edits) => replaceCanvasFindText(
            canvas,
            edits,
            editable: editable,
          ),
        ) {
    canvas.addListener(refresh);
  }

  final CanvasController canvas;

  @override
  void dispose() {
    canvas.removeListener(refresh);
    super.dispose();
  }
}

void replaceCanvasFindText(
  CanvasController canvas,
  List<SurfaceFindReplacement> edits, {
  required bool Function() editable,
}) {
  if (!editable() || edits.isEmpty) return;
  canvas.edit((document) {
    if (!editable()) return document;
    var next = document;
    for (final edit in edits) {
      final id = edit.id;
      if (id is! CanvasFindId || !_replaceable(canvas, id)) continue;
      switch (id.$1) {
        case CanvasHitKind.node:
          final node = next.nodeById(id.$2)!;
          if (id.$3 == CanvasSearchField.title && node.title == edit.before) {
            next = next.withNode(node.copyWith(title: edit.after));
          } else if (id.$3 == CanvasSearchField.text &&
              node.text == edit.before) {
            next = next.withNode(node.copyWith(text: edit.after));
          }
        case CanvasHitKind.frame:
          final frame = next.frameById(id.$2)!;
          if (id.$3 == CanvasSearchField.title && frame.title == edit.before) {
            next = next.withFrame(frame.copyWith(title: edit.after));
          } else if (id.$3 == CanvasSearchField.description &&
              frame.description == edit.before) {
            next = next.withFrame(frame.copyWith(description: edit.after));
          }
        case CanvasHitKind.edge:
          final edge = next.edgeById(id.$2)!;
          if (id.$3 == CanvasSearchField.label && edge.label == edit.before) {
            next = next.withEdge(edge.copyWith(label: edit.after));
          } else if (id.$3 == CanvasSearchField.relation &&
              edge.relation == edit.before) {
            next = next.withEdge(edge.copyWith(relation: edit.after));
          }
      }
    }
    return next;
  });
}
