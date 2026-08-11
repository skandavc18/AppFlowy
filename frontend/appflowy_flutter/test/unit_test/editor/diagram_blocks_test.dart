import 'package:appflowy/shared/drawing/excalidraw.dart';
import 'package:appflowy/shared/mermaid/mermaid.dart';
import 'package:appflowy/shared/mind_map/mind_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MermaidTextMeasurer measurer() => mermaidMeasurer(
        const MermaidTypography(base: TextStyle(), mono: TextStyle()),
      );

  group('reading mermaid source', () {
    test('names the diagram from its first word', () {
      expect(mermaidKindOf('flowchart TD'), MermaidDiagramKind.flowchart);
      expect(mermaidKindOf('graph LR'), MermaidDiagramKind.flowchart);
      expect(mermaidKindOf('sequenceDiagram'), MermaidDiagramKind.sequence);
      expect(mermaidKindOf('classDiagram'), MermaidDiagramKind.classDiagram);
      expect(mermaidKindOf('stateDiagram-v2'), MermaidDiagramKind.state);
      expect(
        mermaidKindOf('erDiagram'),
        MermaidDiagramKind.entityRelationship,
      );
      expect(mermaidKindOf('pie showData'), MermaidDiagramKind.pie);
      expect(mermaidKindOf('mindmap'), MermaidDiagramKind.mindmap);
      expect(mermaidKindOf('gantt'), MermaidDiagramKind.gantt);
      expect(mermaidKindOf('sankey-beta'), MermaidDiagramKind.unsupported);
    });

    test('reads a chain of nodes and links in one statement', () {
      final document = parseMermaid('''
flowchart TD
    A[Start] --> B{Ready?}
    B -->|Yes| C(Process)
    B -->|No| D[[Wait]]
    C --> E((Done))
''');

      final graph = document.graph!;
      expect(graph.direction, MermaidDirection.topToBottom);
      expect(graph.nodes.map((node) => node.id).toSet(),
          {'A', 'B', 'C', 'D', 'E'});
      expect(
        graph.nodes.firstWhere((node) => node.id == 'B').shape,
        MermaidNodeShape.diamond,
      );
      expect(
        graph.nodes.firstWhere((node) => node.id == 'D').shape,
        MermaidNodeShape.subroutine,
      );
      expect(
        graph.nodes.firstWhere((node) => node.id == 'E').shape,
        MermaidNodeShape.circle,
      );
      expect(graph.edges.length, 4);
      expect(
        graph.edges.firstWhere((edge) => edge.to == 'C').label,
        'Yes',
      );
    });

    test('reads a label written between two runs of line characters', () {
      final graph = parseMermaid('graph LR\n  A -- carries --> B').graph!;
      expect(graph.edges.single.label, 'carries');
      expect(graph.edges.single.head, MermaidArrowHead.arrow);
    });

    test('tells a dotted link from a thick one', () {
      final graph = parseMermaid('''
graph LR
  A -.-> B
  B ==> C
  C --- D
''').graph!;
      expect(graph.edges[0].style, MermaidLineStyle.dotted);
      expect(graph.edges[1].style, MermaidLineStyle.thick);
      expect(graph.edges[2].style, MermaidLineStyle.solid);
      expect(graph.edges[2].head, MermaidArrowHead.none);
    });

    test('a plain link is not mistaken for a labelled one', () {
      final graph = parseMermaid('graph LR\n  A --- B').graph!;
      expect(graph.edges.single.label, '');
      expect(graph.nodes.map((node) => node.id), ['A', 'B']);
    });

    test('keeps subgraph membership', () {
      final document = parseMermaid('''
flowchart TB
  subgraph one [First]
    A --> B
  end
  B --> C
''');
      final graph = document.graph!;
      expect(graph.subgraphs.single.label, 'First');
      expect(
        graph.nodes.firstWhere((node) => node.id == 'A').subgraph,
        graph.subgraphs.single.id,
      );
      expect(graph.nodes.firstWhere((node) => node.id == 'C').subgraph, isNull);
    });

    test('drops comments and init directives', () {
      final graph = parseMermaid('''
%%{init: {'theme':'dark'}}%%
graph TD
  %% this is a note
  A --> B
''').graph!;
      expect(graph.nodes.length, 2);
    });

    test('reads a sequence diagram with notes and blocks', () {
      final sequence = parseMermaid('''
sequenceDiagram
    participant U as User
    actor S as Server
    U->>S: Request
    S-->>U: Response
    Note over U,S: A handshake
    loop Every minute
      U->>S: Ping
    end
''').sequence!;

      expect(sequence.actors.map((actor) => actor.label), ['User', 'Server']);
      expect(sequence.actors.last.isActor, isTrue);
      final messages = sequence.steps
          .where((step) => step.kind == MermaidSequenceStepKind.message)
          .toList();
      expect(messages.length, 3);
      expect(messages.first.text, 'Request');
      expect(messages[1].style, MermaidLineStyle.dashed);
      expect(
        sequence.steps.any(
          (step) =>
              step.kind == MermaidSequenceStepKind.note &&
              step.placement == MermaidNotePlacement.over,
        ),
        isTrue,
      );
      expect(
        sequence.steps.any(
          (step) => step.kind == MermaidSequenceStepKind.blockStart,
        ),
        isTrue,
      );
    });

    test('reads class members and the shape of a relation', () {
      final graph = parseMermaid('''
classDiagram
    class Animal {
      +String name
      +speak()
    }
    Animal <|-- Dog
    Dog : +fetch()
''').graph!;

      final animal = graph.nodes.firstWhere((node) => node.id == 'Animal');
      expect(animal.shape, MermaidNodeShape.record);
      expect(animal.members, ['+String name', '+speak()']);
      expect(
        graph.nodes.firstWhere((node) => node.id == 'Dog').members,
        ['+fetch()'],
      );
      expect(graph.edges.single.tail, MermaidArrowHead.triangle);
    });

    test('gives a state diagram a start and an end point', () {
      final graph = parseMermaid('''
stateDiagram-v2
    [*] --> Idle
    Idle --> Running : start
    Running --> [*]
''').graph!;

      expect(
        graph.nodes
            .where((node) => node.shape == MermaidNodeShape.point)
            .length,
        2,
      );
      expect(
        graph.edges.firstWhere((edge) => edge.to == 'Running').label,
        'start',
      );
    });

    test('reads entity cardinality from both ends', () {
      final graph = parseMermaid('''
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER {
      string reference
    }
''').graph!;

      final edge = graph.edges.single;
      expect(edge.tail, MermaidArrowHead.one);
      expect(edge.head, MermaidArrowHead.zeroOrMany);
      expect(edge.label, 'places');
      expect(
        graph.nodes.firstWhere((node) => node.id == 'ORDER').members,
        ['string reference'],
      );
    });

    test('reads a pie chart and its title', () {
      final document = parseMermaid('''
pie showData
    title Where the day goes
    "Focus" : 42
    "Meetings" : 26
''');
      final pie = document.pie!;
      expect(pie.title, 'Where the day goes');
      expect(pie.showData, isTrue);
      expect(pie.slices.map((slice) => slice.label), ['Focus', 'Meetings']);
      expect(pie.total, 68);
    });

    test('builds a mind map from indentation', () {
      final root = parseMermaid('''
mindmap
  root((Project))
    Research
      Interviews
    Build
''').mindmap!;

      expect(root.label, 'Project');
      expect(root.children.map((child) => child.label), ['Research', 'Build']);
      expect(root.children.first.children.single.label, 'Interviews');
    });

    test('reads gantt durations and "after" references', () {
      final gantt = parseMermaid('''
gantt
    title Plan
    dateFormat YYYY-MM-DD
    section Build
      Design    :done, des1, 2024-01-01, 5d
      Implement :active, imp1, after des1, 3d
''').gantt!;

      final tasks = gantt.sections.single.tasks;
      expect(tasks.first.done, isTrue);
      expect(tasks.first.end.difference(tasks.first.start).inDays, 5);
      expect(tasks[1].active, isTrue);
      expect(tasks[1].start, tasks.first.end);
    });

    test('an unreadable diagram is reported rather than thrown', () {
      final document = parseMermaid('sankey-beta\n  a,b,1');
      expect(document.error, isNotNull);
      expect(layoutMermaid(document, measurer()).error, isNotNull);
    });
  });

  group('laying a diagram out', () {
    test('a flowchart is measured and every node is placed', () {
      final scene = layoutMermaid(
        parseMermaid('flowchart TD\n A[Start] --> B[End]'),
        measurer(),
      );
      expect(scene.size.width, greaterThan(0));
      expect(scene.size.height, greaterThan(0));
      expect(scene.shapes.whereType<MermaidBoxShape>().length,
          greaterThanOrEqualTo(2));
      expect(scene.shapes.whereType<MermaidEdgeShape>().length, 1);
    });

    test('a left-to-right chart is wider than it is tall', () {
      final lr = layoutMermaid(
        parseMermaid('graph LR\n A --> B --> C'),
        measurer(),
      );
      final td = layoutMermaid(
        parseMermaid('graph TD\n A --> B --> C'),
        measurer(),
      );
      expect(lr.size.width, greaterThan(lr.size.height));
      expect(td.size.height, greaterThan(td.size.width));
    });

    test('a pie chart draws one arc per slice', () {
      final scene = layoutMermaid(
        parseMermaid('pie\n "A" : 1\n "B" : 3'),
        measurer(),
      );
      final arcs = scene.shapes.whereType<MermaidArcShape>().toList();
      expect(arcs.length, 2);
      expect(arcs[1].sweepAngle, greaterThan(arcs[0].sweepAngle));
    });

    test('a sequence diagram draws a lifeline for each actor', () {
      final scene = layoutMermaid(
        parseMermaid('sequenceDiagram\n A->>B: hello'),
        measurer(),
      );
      expect(scene.shapes.whereType<MermaidEdgeShape>().length,
          greaterThanOrEqualTo(3));
    });

    test('an empty source lays out to nothing', () {
      final scene = layoutMermaid(parseMermaid(''), measurer());
      expect(scene.isEmpty, isTrue);
    });
  });

  group('exporting a diagram', () {
    test('svg carries the size, the shapes and the words', () {
      final render = layoutMermaid(
        parseMermaid('flowchart LR\n A[Hello] --> B[World]'),
        measurer(),
      );
      final svg = mermaidSceneToSvg(
        render,
        mermaidLightPaletteForTest,
        const MermaidTypography(base: TextStyle(), mono: TextStyle()),
      );
      expect(svg, startsWith('<?xml'));
      expect(svg, contains('<svg'));
      expect(svg, contains('Hello'));
      expect(svg, contains('World'));
      expect(svg, contains('</svg>'));
    });
  });

  group('a mind map is a tree that survives a round trip', () {
    test('encodes and decodes without losing anything', () {
      final document = MindMapDocument.blank();
      final restored = MindMapDocument.fromJson(document.toJson());
      expect(restored.root.text, document.root.text);
      expect(restored.nodeCount, document.nodeCount);
    });

    test('adds a child and a sibling in the right places', () {
      var document = MindMapDocument(
        root: MindMapNode(id: 'r', text: 'Root', children: const []),
      );
      document = document.addChild('r', const MindMapNode(id: 'a', text: 'A'));
      document =
          document.addSibling('a', const MindMapNode(id: 'b', text: 'B'));
      expect(document.root.children.map((node) => node.id), ['a', 'b']);
    });

    test('a sibling of the root becomes a child, because a map has one trunk',
        () {
      var document = MindMapDocument(
        root: const MindMapNode(id: 'r', text: 'Root'),
      );
      document =
          document.addSibling('r', const MindMapNode(id: 'x', text: 'X'));
      expect(document.root.id, 'r');
      expect(document.root.children.single.id, 'x');
    });

    test('refuses to drop a branch inside itself', () {
      final document = MindMapDocument(
        root: MindMapNode(
          id: 'r',
          text: 'Root',
          children: [
            MindMapNode(
              id: 'a',
              text: 'A',
              children: const [MindMapNode(id: 'b', text: 'B')],
            ),
          ],
        ),
      );
      final moved = document.move('a', 'b');
      expect(moved.find('a'), isNotNull);
      expect(moved.parentOf('a')!.id, 'r');
    });

    test('removing a node takes its branch with it, and never the root', () {
      final document = MindMapDocument(
        root: MindMapNode(
          id: 'r',
          text: 'Root',
          children: [
            MindMapNode(
              id: 'a',
              text: 'A',
              children: const [MindMapNode(id: 'b', text: 'B')],
            ),
          ],
        ),
      );
      expect(document.remove('a').nodeCount, 1);
      expect(document.remove('r').nodeCount, 3);
    });

    test('reorders among siblings without leaving the list', () {
      var document = MindMapDocument(
        root: const MindMapNode(
          id: 'r',
          text: 'Root',
          children: [
            MindMapNode(id: 'a', text: 'A'),
            MindMapNode(id: 'b', text: 'B'),
          ],
        ),
      );
      document = document.reorder('a', 1);
      expect(document.root.children.map((node) => node.id), ['b', 'a']);
      document = document.reorder('b', -5);
      expect(document.root.children.map((node) => node.id), ['b', 'a']);
    });

    test('reads an indented outline', () {
      final document = mindMapFromOutline('''
- Trip
  - Flights
  - Hotels
    - Check dates
''');
      expect(document.root.text, 'Trip');
      expect(
        document.root.children.map((node) => node.text),
        ['Flights', 'Hotels'],
      );
      expect(document.root.children.last.children.single.text, 'Check dates');
    });

    test('writes an outline and Mermaid source back out', () {
      final document = MindMapDocument(
        root: const MindMapNode(
          id: 'r',
          text: 'Root',
          children: [MindMapNode(id: 'a', text: 'A')],
        ),
      );
      expect(document.toOutline(), '- Root\n  - A\n');
      expect(document.toMermaid(), contains('root((Root))'));
      expect(parseMermaid(document.toMermaid()).mindmap!.label, 'Root');
    });
  });

  group('laying a mind map out', () {
    Size sizer(MindMapNode node, int depth) => const Size(100, 32);

    test('places every visible node and joins each to its parent', () {
      final document = MindMapDocument.blank();
      final layout = layoutMindMap(document, sizer);
      expect(layout.placements.length, document.nodeCount);
      expect(layout.links.length, document.nodeCount - 1);
      expect(layout.size.width, greaterThan(0));
    });

    test('a collapsed branch is not laid out, and says how much it hides', () {
      final document = MindMapDocument(
        root: MindMapNode(
          id: 'r',
          text: 'Root',
          children: [
            MindMapNode(
              id: 'a',
              text: 'A',
              collapsed: true,
              children: const [
                MindMapNode(id: 'b', text: 'B'),
                MindMapNode(id: 'c', text: 'C'),
              ],
            ),
          ],
        ),
      );
      final layout = layoutMindMap(document, sizer);
      expect(layout.placements.map((p) => p.node.id), ['r', 'a']);
      expect(layout.placementFor('a')!.hiddenChildren, 2);
    });

    test('balanced mode grows both ways, rightward mode only one', () {
      final document = MindMapDocument(
        root: MindMapNode(
          id: 'r',
          text: 'Root',
          children: const [
            MindMapNode(id: 'a', text: 'A'),
            MindMapNode(id: 'b', text: 'B'),
          ],
        ),
      );
      final balanced = layoutMindMap(document, sizer);
      expect(
        balanced.placements.map((p) => p.side).toSet(),
        {MindMapSide.right, MindMapSide.left},
      );
      final rightward = layoutMindMap(
        document,
        sizer,
        mode: MindMapLayoutMode.rightward,
      );
      expect(
        rightward.placements
            .where((p) => p.depth > 0)
            .every((p) => p.side == MindMapSide.right),
        isTrue,
      );
    });

    test('hit testing finds the node under a point', () {
      final layout = layoutMindMap(MindMapDocument.blank(), sizer);
      final target = layout.placements.last;
      expect(layout.hitTest(target.rect.center)!.node.id, target.node.id);
      expect(layout.hitTest(const Offset(-500, -500)), isNull);
    });
  });

  group('an excalidraw scene round trips', () {
    test('keeps fields this editor knows nothing about', () {
      const raw = '''
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [
    {
      "id": "one",
      "type": "rectangle",
      "x": 10, "y": 20, "width": 100, "height": 50,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "transparent",
      "boundElements": [{"id": "two", "type": "arrow"}],
      "customData": {"kept": true},
      "index": "a1"
    }
  ],
  "appState": {"viewBackgroundColor": "#ffffff", "someFutureFlag": 7},
  "files": {}
}''';
      final scene = DrawScene.decode(raw)!;
      final element = scene.elements.single;
      expect(element.id, 'one');
      expect(element.type, 'rectangle');
      expect(element.bounds, const Rect.fromLTWH(10, 20, 100, 50));

      final again = DrawScene.decode(scene.encode())!;
      expect(again.elements.single.data['customData'], {'kept': true});
      expect(again.elements.single.data['index'], 'a1');
      expect(again.appState.data['someFutureFlag'], 7);
      expect(again.toJson()['type'], 'excalidraw');
    });

    test('an unreadable scene is refused rather than guessed at', () {
      expect(DrawScene.decode('not json'), isNull);
      expect(DrawScene.decode('')!.isEmpty, isTrue);
    });

    test('a dragged shape with a negative extent still has a sane box', () {
      final element = DrawElement.create(
        type: DrawElementType.rectangle,
        x: 100,
        y: 100,
        width: -40,
        height: -20,
      );
      expect(element.bounds.width, 40);
      expect(element.bounds.left, 60);
    });

    test('linear elements are measured from their points', () {
      final element = DrawElement.create(
        type: DrawElementType.arrow,
        x: 10,
        y: 10,
      ).withPoints([Offset.zero, const Offset(30, 40)]);
      expect(element.bounds, const Rect.fromLTRB(10, 10, 40, 50));
      expect(element.width, 30);
    });

    test('deleted and unknown elements are not drawn', () {
      final scene = DrawScene(
        elements: [
          DrawElement.create(type: DrawElementType.rectangle, x: 0, y: 0)
              .change({'isDeleted': true}),
          DrawElement.create(type: DrawElementType.ellipse, x: 0, y: 0),
          const DrawElement({'id': 'x', 'type': 'frame'}),
        ],
        appState: DrawAppState.initial(),
      );
      expect(scene.visible.length, 1);
      expect(scene.visible.single.type, DrawElementType.ellipse);
    });

    test('layer order is array order', () {
      final a = DrawElement.create(type: DrawElementType.rectangle, x: 0, y: 0);
      final b = DrawElement.create(type: DrawElementType.ellipse, x: 0, y: 0);
      final scene = DrawScene(
        elements: [a, b],
        appState: DrawAppState.initial(),
      );
      expect(scene.bringToFront({a.id}).elements.last.id, a.id);
      expect(scene.sendToBack({b.id}).elements.first.id, b.id);
    });

    test('a colour is read, and transparent means no fill at all', () {
      expect(drawColour('#ff0000', Brightness.light), const Color(0xFFFF0000));
      expect(drawColour('#f00', Brightness.light), const Color(0xFFFF0000));
      expect(drawColour('transparent', Brightness.light), isNull);
      expect(drawColour('', Brightness.light), isNull);
      expect(drawColourToHex(const Color(0xFF3366CC)), '#3366cc');
    });

    test('the same seed always draws the same wobble', () {
      final first = RoughRandom(42);
      final second = RoughRandom(42);
      expect(
        List.generate(5, (_) => first.next()),
        List.generate(5, (_) => second.next()),
      );
    });

    test('svg export carries every visible element', () {
      final scene = DrawScene(
        elements: [
          DrawElement.create(
            type: DrawElementType.rectangle,
            x: 0,
            y: 0,
            width: 40,
            height: 30,
          ),
          DrawElement.create(
            type: DrawElementType.text,
            x: 5,
            y: 5,
            text: 'Sketch',
          ),
        ],
        appState: DrawAppState.initial(),
      );
      final svg = drawSceneToSvg(scene, Brightness.light);
      expect(svg, contains('<svg'));
      expect(svg, contains('Sketch'));
      expect(svg, contains('<path'));
    });

    test('text keeps the lines the editor gave it', () {
      final scene = DrawScene(
        elements: [
          DrawElement(const {
            'id': 'label',
            'type': 'text',
            'x': 10.0,
            'y': 20.0,
            'width': 60.0,
            'height': 50.0,
            'text': 'ne\nw',
            'fontSize': 20.0,
            'fontFamily': 5,
            'textAlign': 'center',
            'verticalAlign': 'middle',
            'lineHeight': 1.25,
          }),
        ],
        appState: DrawAppState.initial(),
      );
      final svg = drawSceneToSvg(scene, Brightness.light);
      expect('<text'.allMatches(svg).length, 2);
      expect(svg, contains('text-anchor="middle"'));
      expect(svg, contains('Excalifont'));
    });

    test('a font family is drawn in the face the editor used', () {
      DrawElement withFamily(int family) => DrawElement({
            'id': 't',
            'type': 'text',
            'text': 'a',
            'fontFamily': family,
          });
      expect(drawFontFamilyFor(withFamily(1)), 'Excalifont');
      expect(drawFontFamilyFor(withFamily(5)), 'Excalifont');
      expect(drawFontFamilyFor(withFamily(3)), 'RobotoMono');
      expect(drawFontFamilyFor(withFamily(2)), isNull);
    });
  });
}

/// A fixed palette so an export test does not need a widget tree.
const mermaidLightPaletteForTest = MermaidPalette(
  canvas: Color(0xFFFFFFFF),
  surface: Color(0xFFF7F7F7),
  surfaceStrong: Color(0xFFEDEDED),
  line: Color(0xFF6B6B6B),
  lineSoft: Color(0xFFD4D4D4),
  text: Color(0xFF1E1E1E),
  textMuted: Color(0xFF6B6B6B),
  accent: Color(0xFF5B8DEF),
  accentSoft: Color(0x1A5B8DEF),
  onAccent: Color(0xFFFFFFFF),
  series: [Color(0xFF5B8DEF), Color(0xFF57B894)],
);
