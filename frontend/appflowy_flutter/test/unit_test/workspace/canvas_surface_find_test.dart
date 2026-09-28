import 'package:appflowy/plugins/canvas/presentation/canvas_find.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _document = CanvasDocument(
  nodes: [
    CanvasNode(
        id: 'plain',
        kind: CanvasNodeKind.text,
        position: Offset.zero,
        size: Size(260, 120),
        text: 'Cat cat scatter'),
    CanvasNode(
        id: 'locked',
        kind: CanvasNodeKind.text,
        locked: true,
        position: Offset(6000, 4000),
        size: Size(260, 120),
        text: 'cat'),
    CanvasNode(
        id: 'linked',
        kind: CanvasNodeKind.page,
        reference: 'page-id',
        position: Offset(1000, 1000),
        size: Size(260, 120),
        title: 'cat'),
    CanvasNode(
        id: 'drawing',
        kind: CanvasNodeKind.diagram,
        position: Offset(2000, 2000),
        size: Size(260, 120),
        text: '{"invisible_secret":"cat"}',
        data: {'diagram': 'drawing'}),
  ],
  frames: [
    CanvasFrame(
        id: 'frame',
        position: Offset(-5000, -4000),
        size: Size(400, 300),
        title: 'cat frame',
        description: 'cat description')
  ],
  edges: [
    CanvasEdge(id: 'edge', from: 'plain', to: 'linked', label: 'cat edge')
  ],
);

void main() {
  test('canvas preserves object search and adds exact option-aware occurrences',
      () {
    expect(searchCanvas(_document, 'cat'), hasLength(6));
    expect(searchCanvas(_document, '   '), isEmpty);
    final hits = searchCanvas(_document, 'cat',
        occurrences: true, options: const FindOptions(wholeWord: true));
    expect(hits, hasLength(7));
    final body = hits.where((hit) => hit.id == 'plain').toList();
    expect(body.map((hit) => hit.match!.start), [0, 4]);
    expect(body.every((hit) => hit.source == 'Cat cat scatter'), isTrue);
    expect(
        searchCanvas(_document, 'Cat',
            occurrences: true, options: const FindOptions(caseSensitive: true)),
        hasLength(1));
    expect(
        searchCanvas(_document, '[',
            occurrences: true, options: const FindOptions(useRegex: true)),
        isEmpty);
    expect(searchCanvas(_document, 'invisible_secret', occurrences: true),
        isEmpty);
  });

  test(
      'canvas replacement guards locks, references and read-only; undo is atomic',
      () {
    final canvas = CanvasController(viewId: '', document: _document);
    var editable = true;
    final find = CanvasFindController(canvas: canvas, editable: () => editable);
    addTearDown(canvas.dispose);
    addTearDown(find.dispose);
    find.open(replace: true);
    find.setOptions(const FindOptions(wholeWord: true));
    find.setQuery('cat');
    find.replacementController.text = 'dog';
    find.replaceAll();
    expect(canvas.document.nodeById('plain')!.text, 'dog dog scatter');
    expect(canvas.document.nodeById('locked')!.text, 'cat');
    expect(canvas.document.nodeById('linked')!.title, 'cat');
    expect(canvas.document.nodeById('drawing'), _document.nodeById('drawing'));
    expect(canvas.document.frameById('frame')!.description, 'dog description');
    expect(canvas.document.edgeById('edge')!.label, 'dog edge');
    canvas.undo();
    expect(canvas.document, _document);
    expect(canvas.canUndo, isFalse);
    editable = false;
    find.replaceAll();
    expect(canvas.document, _document);
    expect(find.supportsReplace, isFalse);
  });

  test('a live canvas editor is not overwritten by Find replacement', () {
    final canvas = CanvasController(viewId: '', document: _document);
    final find = CanvasFindController(canvas: canvas, editable: () => true);
    addTearDown(canvas.dispose);
    addTearDown(find.dispose);
    canvas.beginEditing('plain');
    find.open();
    find.setQuery('Cat');
    expect(
        find.matches
            .where((hit) => (hit.id as CanvasFindId).$2 == 'plain')
            .every((hit) => !hit.entry.replaceable),
        isTrue);
    expect(canvas.document, same(_document));
  });

  test('written diagram source is indexed, serialized drawing payloads are not',
      () {
    final document = _document.withNode(const CanvasNode(
      id: 'source',
      kind: CanvasNodeKind.diagram,
      position: Offset.zero,
      size: Size(300, 200),
      text: 'sourceword sourceword',
      data: {'diagram': 'mermaid'},
    ));
    expect(
        searchCanvas(document, 'sourceword', occurrences: true), hasLength(2));
    expect(
        searchCanvas(document, 'invisible_secret', occurrences: true), isEmpty);
    expect(searchCanvas(document, 'invisible_secret'), hasLength(1),
        reason: 'Legacy object-search callers retain their original contract.');
  });
}
