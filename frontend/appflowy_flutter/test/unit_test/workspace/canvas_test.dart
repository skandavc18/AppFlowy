import 'dart:convert';
import 'dart:ui';

import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_geometry.dart';
import 'package:appflowy/workspace/application/canvas/canvas_layout.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/canvas/canvas_templates.dart';
import 'package:flutter_test/flutter_test.dart';

CanvasNode _card(
  String id, {
  double x = 0,
  double y = 0,
  double width = 200,
  double height = 100,
  String text = '',
  String? frameId,
  int? color,
  CanvasNodeKind kind = CanvasNodeKind.text,
}) =>
    CanvasNode(
      id: id,
      kind: kind,
      position: Offset(x, y),
      size: Size(width, height),
      text: text,
      frameId: frameId,
      color: color,
    );

void main() {
  group('what a canvas remembers', () {
    test('a canvas survives being written down and read back', () {
      final document = CanvasDocument(
        nodes: [
          _card('a', text: 'first'),
          _card('b', x: 400, kind: CanvasNodeKind.page),
        ],
        edges: [
          CanvasEdge.create(id: 'e1', from: 'a', to: 'b', label: 'leads to'),
        ],
        frames: [
          CanvasFrame.create(
            id: 'f1',
            position: const Offset(-40, -40),
            size: const Size(700, 400),
            title: 'Everything',
          ),
        ],
        strokes: [
          CanvasStroke.create(
            id: 's1',
            points: const [Offset(0, 0), Offset(10, 10), Offset(20, 5)],
          ),
        ],
        settings: const CanvasSettings(
          background: CanvasBackground.grid,
          theme: CanvasTheme.blueprint,
          snapToGrid: true,
        ),
      );

      final restored = CanvasDocument.fromJson(
        jsonDecode(jsonEncode(document.toJson())) as Map<String, Object?>,
      );
      expect(restored, document);
    });

    test('the envelope leaves everything else on the view alone', () {
      const other = '{"cover":{"type":"color","value":"blue"}}';
      final extra = CanvasMetadata(document: CanvasDocument.blank())
          .mergeIntoExtra(other);
      final values = jsonDecode(extra) as Map<String, dynamic>;

      expect(values['cover'], isNotNull);
      expect(values[CanvasMetadata.envelopeKey], isNotNull);
      expect(CanvasMetadata.fromExtra(extra), isNotNull);

      // Taking the canvas off again must not take the cover with it.
      final without = CanvasMetadata.removeFromExtra(extra);
      expect(CanvasMetadata.fromExtra(without), isNull);
      expect(
        (jsonDecode(without) as Map<String, dynamic>)['cover'],
        isNotNull,
      );
    });

    test('a connection to a card that is gone is not read back', () {
      final json = {
        'nodes': [
          _card('a').toJson(),
        ],
        'edges': [
          CanvasEdge.create(id: 'e1', from: 'a', to: 'missing').toJson(),
        ],
      };
      expect(CanvasDocument.fromJson(json).edges, isEmpty);
    });

    test('deleting a card takes its connections with it', () {
      final document = CanvasDocument(
        nodes: [_card('a'), _card('b', x: 300)],
        edges: [CanvasEdge.create(id: 'e1', from: 'a', to: 'b')],
      );
      final without = document.without(['b']);
      expect(without.nodes.map((node) => node.id), ['a']);
      expect(without.edges, isEmpty);
    });

    test('deleting a frame frees its cards rather than deleting them', () {
      final document = CanvasDocument(
        nodes: [_card('a', frameId: 'f1')],
        frames: [
          CanvasFrame.create(
            id: 'f1',
            position: Offset.zero,
            size: const Size(400, 300),
          ),
        ],
      );
      final without = document.without(['f1']);
      expect(without.frames, isEmpty);
      expect(without.nodes.single.frameId, isNull);
    });
  });

  group('looking at an infinite plane', () {
    test('a point on screen and a point in the scene agree', () {
      const camera = CanvasCamera(offset: Offset(120, -40), zoom: 1.5);
      const scene = Offset(200, 320);
      expect(
        camera.toScene(camera.toScreen(scene)).dx,
        closeTo(scene.dx, 0.001),
      );
      expect(
        camera.toScene(camera.toScreen(scene)).dy,
        closeTo(scene.dy, 0.001),
      );
    });

    test('zooming keeps whatever is under the pointer under the pointer', () {
      const camera = CanvasCamera(offset: Offset(30, 90));
      const focus = Offset(400, 260);
      final before = camera.toScene(focus);
      final after = camera.zoomedBy(2.4, screenFocus: focus);
      expect(after.toScene(focus).dx, closeTo(before.dx, 0.001));
      expect(after.toScene(focus).dy, closeTo(before.dy, 0.001));
    });

    test('zoom is held between a tenth and four times', () {
      const camera = CanvasCamera();
      expect(camera.zoomedTo(0.001).zoom, minimumCanvasZoom);
      expect(camera.zoomedTo(50).zoom, maximumCanvasZoom);
    });

    test('fitting frames the content and never blows one card up', () {
      final camera = CanvasCamera.fittedTo(
        const Rect.fromLTWH(0, 0, 100, 80),
        const Size(1200, 800),
      );
      // A canvas holding one small card should not open with it filling the
      // window, so the fit is capped.
      expect(camera.zoom, lessThanOrEqualTo(1.2));
      final centre = camera.toScene(const Offset(600, 400));
      expect(centre.dx, closeTo(50, 0.5));
      expect(centre.dy, closeTo(40, 0.5));
    });

    test('what the camera can see is what a viewport covers', () {
      const camera = CanvasCamera(offset: Offset(-100, -50), zoom: 2);
      final visible = camera.visibleScene(const Size(400, 200));
      expect(visible.left, closeTo(50, 0.001));
      expect(visible.top, closeTo(25, 0.001));
      expect(visible.width, closeTo(200, 0.001));
    });
  });

  group('lining things up', () {
    test('a dragged card settles against its neighbour', () {
      final snap = snapCanvasRect(
        moving: const Rect.fromLTWH(103, 40, 100, 60),
        neighbours: const [Rect.fromLTWH(100, 200, 100, 60)],
      );
      expect(snap.position.dx, 100);
      expect(snap.guides.where((guide) => guide.vertical), isNotEmpty);
    });

    test('nothing snaps when the neighbours are far away', () {
      final snap = snapCanvasRect(
        moving: const Rect.fromLTWH(103, 40, 100, 60),
        neighbours: const [Rect.fromLTWH(600, 900, 100, 60)],
      );
      expect(snap.position, const Offset(103, 40));
      expect(snap.guides, isEmpty);
    });

    test('the grid is only used when it has been asked for', () {
      const moving = Rect.fromLTWH(31, 47, 100, 60);
      expect(
        snapCanvasRect(
          moving: moving,
          neighbours: const [],
          gridSize: 20,
          snapToObjects: false,
        ).position,
        const Offset(31, 47),
      );
      expect(
        snapCanvasRect(
          moving: moving,
          neighbours: const [],
          gridSize: 20,
          snapToGrid: true,
          snapToObjects: false,
        ).position,
        const Offset(40, 40),
      );
    });

    test('aligning left moves everything to the leftmost edge', () {
      final moved = alignCanvasRects(
        const {
          'a': Rect.fromLTWH(10, 0, 100, 50),
          'b': Rect.fromLTWH(80, 100, 100, 50),
        },
        CanvasAlign.left,
      );
      expect(moved['b'], const Offset(10, 100));
      // The card that is already there does not need moving, so it is not
      // reported — the result is a patch.
      expect(moved.containsKey('a'), isFalse);
    });

    test('distributing keeps the outermost two where they are', () {
      final moved = distributeCanvasRects(
        const {
          'a': Rect.fromLTWH(0, 0, 100, 50),
          'b': Rect.fromLTWH(120, 0, 100, 50),
          'c': Rect.fromLTWH(400, 0, 100, 50),
        },
        CanvasAxis.horizontal,
      );
      expect(moved.containsKey('a'), isFalse);
      expect(moved.containsKey('c'), isFalse);
      expect(moved['b']!.dx, closeTo(200, 0.001));
    });

    test('equal gaps really are equal', () {
      final moved = spaceCanvasRects(
        const {
          'a': Rect.fromLTWH(0, 0, 100, 50),
          'b': Rect.fromLTWH(180, 0, 60, 50),
          'c': Rect.fromLTWH(400, 0, 100, 50),
        },
        CanvasAxis.horizontal,
        gap: 20,
      );
      expect(moved['b']!.dx, 120);
      expect(moved['c']!.dx, 200);
    });
  });

  group('drawing a connection', () {
    test('a card connects from the side that faces the other', () {
      expect(
        resolveCanvasSide(
          const Rect.fromLTWH(0, 0, 100, 100),
          const Rect.fromLTWH(400, 0, 100, 100),
        ),
        CanvasSide.right,
      );
      expect(
        resolveCanvasSide(
          const Rect.fromLTWH(0, 0, 100, 100),
          const Rect.fromLTWH(0, 400, 100, 100),
        ),
        CanvasSide.bottom,
      );
    });

    test('the curve begins and ends on the cards it joins', () {
      const from = Rect.fromLTWH(0, 0, 100, 100);
      const to = Rect.fromLTWH(400, 0, 100, 100);
      final geometry = canvasEdgeGeometry(from: from, to: to);
      expect(geometry.start, const Offset(100, 50));
      expect(geometry.end, const Offset(400, 50));
      // The curve leaves square to the edge, so its first control point is
      // further right than where it started.
      expect(geometry.controlStart.dx, greaterThan(geometry.start.dx));
    });

    test('the pointer finds a connection near it and misses one far away', () {
      final geometry = canvasEdgeGeometry(
        from: const Rect.fromLTWH(0, 0, 100, 100),
        to: const Rect.fromLTWH(400, 0, 100, 100),
      );
      expect(geometry.distanceTo(const Offset(250, 50)), lessThan(6));
      expect(geometry.distanceTo(const Offset(250, 400)), greaterThan(100));
    });
  });

  group('finding a free spot', () {
    test('a card is put where it was asked for when nothing is there', () {
      expect(
        findFreeCanvasSpot(
          near: const Offset(100, 100),
          size: const Size(200, 100),
          taken: const [],
        ),
        const Offset(100, 100),
      );
    });

    test('a card lands beside what is already there, not on top of it', () {
      final spot = findFreeCanvasSpot(
        near: const Offset(100, 100),
        size: const Size(200, 100),
        taken: const [Rect.fromLTWH(100, 100, 200, 100)],
      );
      expect(spot, isNot(const Offset(100, 100)));
      expect(
        (spot & const Size(200, 100))
            .overlaps(const Rect.fromLTWH(100, 100, 200, 100)),
        isFalse,
      );
    });
  });

  group('what a marquee catches', () {
    test('a box the marquee touches is caught', () {
      final caught = canvasObjectsIn(
        const Rect.fromLTWH(0, 0, 150, 150),
        const {
          'inside': Rect.fromLTWH(10, 10, 50, 50),
          'touching': Rect.fromLTWH(140, 140, 200, 200),
          'far': Rect.fromLTWH(900, 900, 50, 50),
        },
      );
      expect(caught, {'inside', 'touching'});
    });

    test('a marquee dragged upwards catches the same things', () {
      final caught = canvasObjectsIn(
        const Rect.fromLTRB(150, 150, 0, 0),
        const {'inside': Rect.fromLTWH(10, 10, 50, 50)},
      );
      expect(caught, {'inside'});
    });
  });

  group('arranging a canvas', () {
    test('a flow follows the connections from left to right', () {
      final document = CanvasDocument(
        nodes: [
          _card('a', x: 500, y: 300),
          _card('b'),
          _card('c', x: 200, y: 700),
        ],
        edges: [
          CanvasEdge.create(id: 'e1', from: 'a', to: 'b'),
          CanvasEdge.create(id: 'e2', from: 'b', to: 'c'),
        ],
      );
      final placed = layOutCanvas(document, kind: CanvasLayoutKind.flow);
      expect(placed['a']!.dx, lessThan(placed['b']!.dx));
      expect(placed['b']!.dx, lessThan(placed['c']!.dx));
    });

    test('a tree grows downwards', () {
      final document = CanvasDocument(
        nodes: [
          _card('a', x: 300, y: 900),
          _card('b', x: 40, y: 40),
          _card('c', x: 700, y: 60),
        ],
        edges: [
          CanvasEdge.create(id: 'e1', from: 'a', to: 'b'),
          CanvasEdge.create(id: 'e2', from: 'a', to: 'c'),
        ],
      );
      final placed = layOutCanvas(document);
      expect(placed['b']!.dy, greaterThan(placed['a']!.dy));
      expect(placed['c']!.dy, placed['b']!.dy);
    });

    test('a mind map balances its branches either side of the centre', () {
      final document = CanvasDocument(
        nodes: [
          _card('centre'),
          _card('one'),
          _card('two'),
          _card('three'),
          _card('four'),
        ],
        edges: [
          CanvasEdge.create(id: 'e1', from: 'centre', to: 'one'),
          CanvasEdge.create(id: 'e2', from: 'centre', to: 'two'),
          CanvasEdge.create(id: 'e3', from: 'centre', to: 'three'),
          CanvasEdge.create(id: 'e4', from: 'centre', to: 'four'),
        ],
      );
      final placed = layOutCanvas(document, kind: CanvasLayoutKind.mindMap);
      final centre = placed['centre'] ?? Offset.zero;
      final right = [
        for (final id in ['one', 'two', 'three', 'four'])
          if ((placed[id] ?? Offset.zero).dx > centre.dx) id,
      ];
      expect(right.length, 2);
    });

    test('a canvas with no connections is simply tidied into a grid', () {
      final document = CanvasDocument(
        nodes: [
          _card('a', x: 13, y: 7),
          _card('b', x: 300, y: 40),
          _card('c', x: 90, y: 400),
        ],
      );
      final placed = layOutCanvas(document, kind: CanvasLayoutKind.grid);
      expect(placed.length, greaterThan(0));
      // Reading order is kept, so tidying up does not shuffle the ideas: the
      // card that was lowest is still on a later row. A card already in the
      // right place is left out of the patch, so read through to where it is.
      Offset at(String id) => placed[id] ?? document.nodeById(id)!.position;
      expect(at('a').dy, lessThanOrEqualTo(at('c').dy));
      expect(at('b').dy, at('a').dy);
    });

    test('arranging one card alone does nothing', () {
      final document = CanvasDocument(nodes: [_card('a')]);
      expect(layOutCanvas(document), isEmpty);
    });

    test('a ring of connections still arranges rather than looping for ever',
        () {
      final document = CanvasDocument(
        nodes: [_card('a'), _card('b'), _card('c')],
        edges: [
          CanvasEdge.create(id: 'e1', from: 'a', to: 'b'),
          CanvasEdge.create(id: 'e2', from: 'b', to: 'c'),
          CanvasEdge.create(id: 'e3', from: 'c', to: 'a'),
        ],
      );
      expect(layOutCanvas(document).length, greaterThan(0));
    });
  });

  group('working on a canvas', () {
    late CanvasController controller;

    setUp(() {
      controller = CanvasController(
        // No view id means nothing is ever written, which is what a test of
        // the model wants.
        viewId: '',
        document: CanvasDocument(
          nodes: [_card('a'), _card('b', x: 400)],
        ),
      );
    });

    tearDown(() => controller.dispose());

    test('a whole drag is one thing to undo', () {
      // What the board does: every frame of the drag is transient, and the
      // document as it was before the gesture is committed once at the end.
      final before = controller.document;
      for (var step = 1; step <= 20; step++) {
        controller.edit(
          (document) => document.withNode(
            document.nodeById('a')!.copyWith(position: Offset(4.0 * step, 0)),
          ),
          transient: true,
        );
      }
      controller.commitGesture(before);
      expect(controller.document.nodeById('a')!.position.dx, 80);

      controller.undo();
      // One undo puts the card back where the drag started, not one step back.
      expect(controller.document.nodeById('a')!.position.dx, 0);
      controller.redo();
      expect(controller.document.nodeById('a')!.position.dx, 80);
    });

    test('a gesture that changed nothing is not remembered', () {
      controller.select(['a']);
      controller.moveSelection(const Offset(10, 0));
      final before = controller.document;
      controller.commitGesture(before);

      controller.undo();
      // The empty commit must not have eaten the move that came before it.
      expect(controller.document.nodeById('a')!.position, Offset.zero);
    });

    test('nudging with the keyboard is one thing to undo each time', () {
      controller.select(['a']);
      controller.moveSelection(const Offset(2, 0));
      controller.moveSelection(const Offset(2, 0));
      expect(controller.document.nodeById('a')!.position.dx, 4);
      controller.undo();
      expect(controller.document.nodeById('a')!.position.dx, 2);
    });

    test('undo and redo walk the same path', () {
      controller.select(['a']);
      controller.moveSelection(const Offset(50, 50));
      controller.undo();
      expect(controller.document.nodeById('a')!.position, Offset.zero);
      controller.redo();
      expect(controller.document.nodeById('a')!.position, const Offset(50, 50));
    });

    test('a moved frame carries what it holds', () {
      controller
        ..edit(
          (document) => document.copyWith(
            frames: [
              CanvasFrame.create(
                id: 'f1',
                position: Offset.zero,
                size: const Size(600, 400),
              ),
            ],
            nodes: [
              _card('a', frameId: 'f1'),
              _card('b', x: 400),
            ],
          ),
        )
        ..select(['f1'])
        ..moveSelection(const Offset(100, 0));

      expect(controller.document.nodeById('a')!.position.dx, 100);
      // A card outside the frame stays where it was.
      expect(controller.document.nodeById('b')!.position.dx, 400);
    });

    test('the same two cards are never joined twice', () {
      final first = controller.connect('a', 'b');
      final second = controller.connect('a', 'b');
      expect(controller.document.edges.length, 1);
      expect(second, first);
    });

    test('a card cannot be joined to itself', () {
      expect(controller.connect('a', 'a'), isNull);
      expect(controller.document.edges, isEmpty);
    });

    test('grouping puts a frame round the selection and files the cards', () {
      controller.select(['a', 'b']);
      final frameId = controller.groupSelection();
      expect(frameId, isNotNull);

      final frame = controller.document.frameById(frameId!)!;
      expect(frame.rect.contains(const Offset(100, 50)), isTrue);
      expect(controller.document.nodesInFrame(frameId).length, 2);
    });

    test('duplicating copies the connection between what was copied', () {
      controller
        ..connect('a', 'b')
        ..select(['a', 'b']);
      final made = controller.duplicateSelection();

      expect(made.length, 2);
      expect(controller.document.nodes.length, 4);
      expect(controller.document.edges.length, 2);
      // The copy's connection joins the copies, not the originals.
      final copied = controller.document.edges.last;
      expect(made.contains(copied.from), isTrue);
      expect(made.contains(copied.to), isTrue);
    });

    test('a card dropped over a frame joins it', () {
      controller
        ..edit(
          (document) => document.copyWith(
            frames: [
              CanvasFrame.create(
                id: 'f1',
                position: const Offset(300, -50),
                size: const Size(400, 400),
              ),
            ],
          ),
        )
        ..adoptFrameForNode('b');
      expect(controller.document.nodeById('b')!.frameId, 'f1');

      controller.adoptFrameForNode('a');
      expect(controller.document.nodeById('a')!.frameId, isNull);
    });

    test('a setting is not something to undo', () {
      controller
        ..select(['a'])
        ..moveSelection(const Offset(30, 0))
        ..updateSettings(
          (settings) => settings.copyWith(background: CanvasBackground.lines),
        )
        ..undo();

      // Undoing the move must not also turn the lines back off.
      expect(controller.settings.background, CanvasBackground.lines);
      expect(controller.document.nodeById('a')!.position, Offset.zero);
    });

    test('colouring reaches the connections inside the selection', () {
      controller
        ..connect('a', 'b')
        ..select(['a', 'b'])
        ..colourSelection(3);
      expect(controller.document.edges.single.color, 3);
      expect(controller.document.nodeById('a')!.color, 3);
    });
  });

  group('finding something on a canvas', () {
    final document = CanvasDocument(
      nodes: [
        _card('a', text: 'The scheduler runs every hour', frameId: 'f1'),
        CanvasNode(
          id: 'b',
          kind: CanvasNodeKind.page,
          position: const Offset(400, 0),
          size: const Size(200, 100),
          title: 'Scheduler design',
        ),
        _card('c', text: 'Nothing to do with it', frameId: 'f1'),
      ],
      edges: [
        CanvasEdge.create(id: 'e1', from: 'a', to: 'b', label: 'described by'),
      ],
      frames: [
        CanvasFrame.create(
          id: 'f1',
          position: Offset.zero,
          size: const Size(800, 400),
          title: 'Backend',
        ),
      ],
    );

    test('a search reads titles, text and labels', () {
      final hits = searchCanvas(document, 'scheduler');
      expect(hits.map((hit) => hit.id), containsAll(['a', 'b']));
      // A title match leads, because that is usually what was meant.
      expect(hits.first.id, 'b');
    });

    test('an empty query finds nothing rather than everything', () {
      expect(searchCanvas(document, '   '), isEmpty);
    });

    test('a connection is found by its label', () {
      expect(
        searchCanvas(document, 'described').single.kind,
        CanvasHitKind.edge,
      );
    });

    test('the outline lists frames and named cards, not everything', () {
      final outline = canvasOutline(document);
      expect(outline.first.id, 'f1');
      // Cards inside a frame are not repeated at the top level.
      expect(outline.map((entry) => entry.id), isNot(contains('a')));
      expect(outline.map((entry) => entry.id), contains('b'));
    });
  });

  group('what a template puts down', () {
    test('every template builds something that can be read back', () {
      for (final template in canvasTemplates()) {
        final built = template.build();
        final restored = CanvasDocument.fromJson(
          jsonDecode(jsonEncode(built.toJson())) as Map<String, Object?>,
        );
        expect(restored, built, reason: template.id);
      }
    });

    test('only the blank template is empty', () {
      for (final template in canvasTemplates()) {
        expect(
          template.build().isEmpty,
          template.id == 'blank',
          reason: template.id,
        );
      }
    });

    test('every card a template files under a frame has one that exists', () {
      for (final template in canvasTemplates()) {
        final built = template.build();
        final frames = {for (final frame in built.frames) frame.id};
        for (final node in built.nodes) {
          final frameId = node.frameId;
          if (frameId != null) {
            expect(frames, contains(frameId), reason: template.id);
          }
        }
      }
    });

    test('every connection a template draws joins two of its own cards', () {
      for (final template in canvasTemplates()) {
        final built = template.build();
        final ids = {for (final node in built.nodes) node.id};
        for (final edge in built.edges) {
          expect(ids, contains(edge.from), reason: template.id);
          expect(ids, contains(edge.to), reason: template.id);
        }
      }
    });

    test('a template can be found by its id', () {
      expect(canvasTemplateById('mind_map'), isNotNull);
      expect(canvasTemplateById('nothing_like_this'), isNull);
    });
  });

  group('a card that has not been told what it holds', () {
    test('every kind that needs asking says so', () {
      const wanting = {
        CanvasNodeKind.image,
        CanvasNodeKind.web,
        CanvasNodeKind.bookmark,
        CanvasNodeKind.page,
        CanvasNodeKind.database,
        CanvasNodeKind.canvas,
        CanvasNodeKind.file,
        CanvasNodeKind.diagram,
      };
      for (final kind in CanvasNodeKind.values) {
        final node = CanvasNode.create(kind: kind, position: Offset.zero);
        expect(node.needsSetUp, wanting.contains(kind), reason: kind.id);
      }
    });

    test('a card stops asking once it has been told', () {
      final picture = CanvasNode.create(
        kind: CanvasNodeKind.image,
        position: Offset.zero,
      );
      expect(picture.needsSetUp, isTrue);
      expect(picture.copyWith(url: 'C:/photo.png').needsSetUp, isFalse);

      final page = CanvasNode.create(
        kind: CanvasNodeKind.page,
        position: Offset.zero,
      );
      expect(page.copyWith(reference: 'view-1').needsSetUp, isFalse);
    });

    test('a diagram is not ready until its sort has been chosen', () {
      final diagram = CanvasNode.create(
        kind: CanvasNodeKind.diagram,
        position: Offset.zero,
      );
      expect(diagram.needsSetUp, isTrue);
      expect(diagram.diagramKind, isNull);

      final drawn =
          diagram.withData(canvasDiagramKindKey, CanvasDiagramKind.drawing.id);
      expect(drawn.needsSetUp, isFalse);
      expect(drawn.diagramKind, CanvasDiagramKind.drawing);

      final written =
          diagram.withData(canvasDiagramKindKey, CanvasDiagramKind.mermaid.id);
      expect(written.diagramKind, CanvasDiagramKind.mermaid);
    });

    test('only the kinds that are typed into are opened for typing', () {
      CanvasNode of(CanvasNodeKind kind) =>
          CanvasNode.create(kind: kind, position: Offset.zero);

      expect(of(CanvasNodeKind.text).typesItsOwnText, isTrue);
      expect(of(CanvasNodeKind.code).typesItsOwnText, isTrue);
      expect(of(CanvasNodeKind.image).typesItsOwnText, isFalse);
      // A hand-drawn diagram is emphatically not typed into, even though a
      // written one shares its card kind.
      expect(
        of(CanvasNodeKind.diagram)
            .withData(canvasDiagramKindKey, CanvasDiagramKind.drawing.id)
            .typesItsOwnText,
        isFalse,
      );
      expect(
        of(CanvasNodeKind.diagram)
            .withData(canvasDiagramKindKey, CanvasDiagramKind.mermaid.id)
            .typesItsOwnText,
        isTrue,
      );
    });

    test('the sort of diagram survives being written down', () {
      final document = CanvasDocument(
        nodes: [
          CanvasNode.create(
            kind: CanvasNodeKind.diagram,
            position: Offset.zero,
            data: {canvasDiagramKindKey: CanvasDiagramKind.drawing.id},
            id: 'd',
          ),
        ],
      );
      final restored = CanvasDocument.fromJson(
        jsonDecode(jsonEncode(document.toJson())) as Map<String, Object?>,
      );
      expect(
        restored.nodeById('d')!.diagramKind,
        CanvasDiagramKind.drawing,
      );
    });
  });

  group('a picture takes its own shape', () {
    test('a landscape photograph makes a landscape card', () {
      final size = canvasImageSizeFor(const Size(4000, 3000));
      expect(size.width / size.height, closeTo(4 / 3, 0.001));
      expect(size.width, lessThanOrEqualTo(maximumCanvasImageSize.width));
      expect(size.height, lessThanOrEqualTo(maximumCanvasImageSize.height));
    });

    test('a tall photograph makes a tall card', () {
      final size = canvasImageSizeFor(const Size(1080, 1920));
      expect(size.height, greaterThan(size.width));
      expect(size.height, lessThanOrEqualTo(maximumCanvasImageSize.height));
    });

    test('a small picture is shown at its own size, not blown up', () {
      final size = canvasImageSizeFor(const Size(180, 120));
      expect(size.width, 180);
      expect(size.height, 120);
    });

    test('a picture too small to be a card is still a card', () {
      final size = canvasImageSizeFor(const Size(16, 16));
      expect(size.width, greaterThanOrEqualTo(minimumCanvasNodeWidth));
      expect(size.height, greaterThanOrEqualTo(minimumCanvasNodeHeight));
    });

    test('a picture with no size at all falls back to the default', () {
      expect(
        canvasImageSizeFor(Size.zero),
        defaultCanvasNodeSize(CanvasNodeKind.image),
      );
    });
  });

  group('mind map keys', () {
    test('a branch goes beside its parent, under the last one made', () {
      const parent = Rect.fromLTWH(0, 0, 200, 100);
      final first = nextMindMapChildPosition(
        parent: parent,
        siblings: const [],
        size: const Size(180, 90),
      );
      expect(first.dx, greaterThan(parent.right));

      final second = nextMindMapChildPosition(
        parent: parent,
        siblings: [first & const Size(180, 90)],
        size: const Size(180, 90),
      );
      expect(second.dy, greaterThan(first.dy));
      expect(second.dx, first.dx);
    });

    test('a sibling goes directly under the one it is beside', () {
      const sibling = Rect.fromLTWH(300, 100, 180, 90);
      final next = nextMindMapSiblingPosition(
        sibling: sibling,
        size: const Size(180, 90),
      );
      expect(next.dx, sibling.left);
      expect(next.dy, greaterThan(sibling.bottom));
    });
  });
}
