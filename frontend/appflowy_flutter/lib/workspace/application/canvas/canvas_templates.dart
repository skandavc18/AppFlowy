import 'dart:ui' show Offset, Size;

import 'package:appflowy/workspace/application/canvas/canvas_model.dart';

/// A template only ever puts objects on a canvas. Nothing it makes is special
/// afterwards: every card, frame and connection is exactly what somebody would
/// have drawn by hand, and can be changed or thrown away.
class CanvasTemplate {
  const CanvasTemplate({
    required this.id,
    required this.nameKey,
    required this.descriptionKey,
    required this.build,
  });

  final String id;

  /// A `LocaleKeys.*` path, resolved by the caller so this file stays pure.
  final String nameKey;
  final String descriptionKey;

  final CanvasDocument Function() build;
}

List<CanvasTemplate> canvasTemplates() => const [
      CanvasTemplate(
        id: 'blank',
        nameKey: 'canvas.templates.blank.name',
        descriptionKey: 'canvas.templates.blank.description',
        build: _blank,
      ),
      CanvasTemplate(
        id: 'mind_map',
        nameKey: 'canvas.templates.mindMap.name',
        descriptionKey: 'canvas.templates.mindMap.description',
        build: _mindMap,
      ),
      CanvasTemplate(
        id: 'brainstorm',
        nameKey: 'canvas.templates.brainstorm.name',
        descriptionKey: 'canvas.templates.brainstorm.description',
        build: _brainstorm,
      ),
      CanvasTemplate(
        id: 'project',
        nameKey: 'canvas.templates.project.name',
        descriptionKey: 'canvas.templates.project.description',
        build: _project,
      ),
      CanvasTemplate(
        id: 'architecture',
        nameKey: 'canvas.templates.architecture.name',
        descriptionKey: 'canvas.templates.architecture.description',
        build: _architecture,
      ),
      CanvasTemplate(
        id: 'research',
        nameKey: 'canvas.templates.research.name',
        descriptionKey: 'canvas.templates.research.description',
        build: _research,
      ),
      CanvasTemplate(
        id: 'journey',
        nameKey: 'canvas.templates.journey.name',
        descriptionKey: 'canvas.templates.journey.description',
        build: _journey,
      ),
      CanvasTemplate(
        id: 'swot',
        nameKey: 'canvas.templates.swot.name',
        descriptionKey: 'canvas.templates.swot.description',
        build: _swot,
      ),
      CanvasTemplate(
        id: 'kanban',
        nameKey: 'canvas.templates.kanban.name',
        descriptionKey: 'canvas.templates.kanban.description',
        build: _kanban,
      ),
      CanvasTemplate(
        id: 'meeting',
        nameKey: 'canvas.templates.meeting.name',
        descriptionKey: 'canvas.templates.meeting.description',
        build: _meeting,
      ),
      CanvasTemplate(
        id: 'study',
        nameKey: 'canvas.templates.study.name',
        descriptionKey: 'canvas.templates.study.description',
        build: _study,
      ),
      CanvasTemplate(
        id: 'roadmap',
        nameKey: 'canvas.templates.roadmap.name',
        descriptionKey: 'canvas.templates.roadmap.description',
        build: _roadmap,
      ),
    ];

CanvasTemplate? canvasTemplateById(String id) {
  for (final template in canvasTemplates()) {
    if (template.id == id) {
      return template;
    }
  }
  return null;
}

CanvasDocument _blank() => CanvasDocument.blank();

// ---------------------------------------------------------------------------
// Builders. Each one lays its objects out at sensible coordinates so the
// canvas opens looking arranged rather than needing a tidy-up first.
// ---------------------------------------------------------------------------

CanvasNode _card(
  String id,
  String text, {
  required double x,
  required double y,
  double width = 220,
  double height = 96,
  int? color,
  String? frameId,
  String title = '',
}) =>
    CanvasNode(
      id: id,
      kind: CanvasNodeKind.text,
      position: Offset(x, y),
      size: Size(width, height),
      title: title,
      text: text,
      color: color,
      frameId: frameId,
    );

CanvasFrame _frame(
  String id,
  String title, {
  required double x,
  required double y,
  required double width,
  required double height,
  int? color,
  String description = '',
}) =>
    CanvasFrame(
      id: id,
      position: Offset(x, y),
      size: Size(width, height),
      title: title,
      description: description,
      color: color,
    );

CanvasEdge _link(
  String from,
  String to, {
  String label = '',
  CanvasEdgeMarker endMarker = CanvasEdgeMarker.arrow,
}) =>
    CanvasEdge(
      id: 'e_${from}_$to',
      from: from,
      to: to,
      label: label,
      endMarker: endMarker,
    );

CanvasDocument _mindMap() => CanvasDocument(
      nodes: [
        _card(
          'centre',
          'Central idea',
          x: 0,
          y: 0,
          width: 200,
          height: 84,
          color: 0,
        ),
        _card('b1', 'Branch one', x: 320, y: -160, width: 180),
        _card('b2', 'Branch two', x: 320, y: -30, width: 180),
        _card('b3', 'Branch three', x: 320, y: 100, width: 180),
        _card('b4', 'Branch four', x: -260, y: -30, width: 180),
      ],
      edges: [
        _link('centre', 'b1', endMarker: CanvasEdgeMarker.none),
        _link('centre', 'b2', endMarker: CanvasEdgeMarker.none),
        _link('centre', 'b3', endMarker: CanvasEdgeMarker.none),
        _link('centre', 'b4', endMarker: CanvasEdgeMarker.none),
      ],
    );

CanvasDocument _brainstorm() => CanvasDocument(
      frames: [
        _frame('ideas', 'Ideas', x: 0, y: 0, width: 560, height: 420, color: 4),
        _frame(
          'keep',
          'Worth keeping',
          x: 620,
          y: 0,
          width: 380,
          height: 420,
          color: 1,
        ),
      ],
      nodes: [
        _card('i1', 'What if…', x: 32, y: 64, frameId: 'ideas', color: 4),
        _card('i2', 'Another angle', x: 292, y: 64, frameId: 'ideas'),
        _card('i3', 'A wild one', x: 32, y: 196, frameId: 'ideas'),
        _card('i4', 'Something small', x: 292, y: 196, frameId: 'ideas'),
        _card(
          'k1',
          'The one to try first',
          x: 652,
          y: 64,
          frameId: 'keep',
          color: 1,
        ),
      ],
    );

CanvasDocument _project() => CanvasDocument(
      frames: [
        _frame('now', 'Now', x: 0, y: 0, width: 320, height: 460, color: 1),
        _frame('next', 'Next', x: 360, y: 0, width: 320, height: 460, color: 2),
        _frame(
          'later',
          'Later',
          x: 720,
          y: 0,
          width: 320,
          height: 460,
          color: 5,
        ),
      ],
      nodes: [
        _card(
          'n1',
          'The task in hand',
          x: 24,
          y: 60,
          width: 272,
          frameId: 'now',
          color: 1,
        ),
        _card(
          'n2',
          'And the one after it',
          x: 24,
          y: 176,
          width: 272,
          frameId: 'now',
        ),
        _card(
          'x1',
          'Waiting on something',
          x: 384,
          y: 60,
          width: 272,
          frameId: 'next',
        ),
        _card('l1', 'Some day', x: 744, y: 60, width: 272, frameId: 'later'),
      ],
      settings: const CanvasSettings(background: CanvasBackground.grid),
    );

CanvasDocument _architecture() => CanvasDocument(
      frames: [
        _frame(
          'edge',
          'Edge',
          x: -40,
          y: -60,
          width: 360,
          height: 240,
          color: 0,
        ),
        _frame(
          'services',
          'Services',
          x: 400,
          y: -60,
          width: 400,
          height: 400,
          color: 2,
        ),
        _frame(
          'data',
          'Data',
          x: 880,
          y: -60,
          width: 320,
          height: 400,
          color: 5,
        ),
      ],
      nodes: [
        _card(
          'client',
          'Client',
          x: -8,
          y: 0,
          width: 140,
          height: 72,
          frameId: 'edge',
        ),
        _card(
          'gateway',
          'API gateway',
          x: 160,
          y: 0,
          width: 140,
          height: 72,
          frameId: 'edge',
          color: 0,
        ),
        _card(
          'api',
          'API',
          x: 432,
          y: 0,
          width: 160,
          height: 72,
          frameId: 'services',
        ),
        _card(
          'scheduler',
          'Scheduler',
          x: 432,
          y: 130,
          width: 160,
          height: 72,
          frameId: 'services',
        ),
        _card(
          'worker',
          'Worker',
          x: 432,
          y: 260,
          width: 160,
          height: 72,
          frameId: 'services',
        ),
        _card(
          'db',
          'Database',
          x: 912,
          y: 0,
          width: 160,
          height: 72,
          frameId: 'data',
          color: 5,
        ),
        _card(
          'queue',
          'Queue',
          x: 912,
          y: 130,
          width: 160,
          height: 72,
          frameId: 'data',
        ),
      ],
      edges: [
        _link('client', 'gateway'),
        _link('gateway', 'api', label: 'requests'),
        _link('api', 'db', label: 'reads'),
        _link('api', 'queue', label: 'enqueues'),
        _link('scheduler', 'worker', label: 'triggers'),
        _link('worker', 'db', label: 'writes'),
      ],
      settings: const CanvasSettings(background: CanvasBackground.grid),
    );

CanvasDocument _research() => CanvasDocument(
      frames: [
        _frame(
          'question',
          'Question',
          x: 0,
          y: 0,
          width: 380,
          height: 220,
          color: 0,
        ),
        _frame(
          'sources',
          'Sources',
          x: 0,
          y: 260,
          width: 380,
          height: 380,
          color: 2,
        ),
        _frame(
          'findings',
          'Findings',
          x: 440,
          y: 0,
          width: 420,
          height: 640,
          color: 1,
        ),
      ],
      nodes: [
        _card(
          'q',
          'What am I actually asking?',
          x: 24,
          y: 60,
          width: 332,
          frameId: 'question',
          color: 0,
        ),
        _card(
          's1',
          'A paper worth reading',
          x: 24,
          y: 320,
          width: 332,
          frameId: 'sources',
        ),
        _card(
          's2',
          'Someone who has done this',
          x: 24,
          y: 440,
          width: 332,
          frameId: 'sources',
        ),
        _card(
          'f1',
          'What I found out',
          x: 464,
          y: 60,
          width: 372,
          frameId: 'findings',
          color: 1,
        ),
      ],
      edges: [
        _link('q', 'f1', label: 'answers'),
        _link('s1', 'f1', endMarker: CanvasEdgeMarker.none),
      ],
    );

CanvasDocument _journey() => CanvasDocument(
      nodes: [
        _card('j1', 'Hears about it', x: 0, y: 0, width: 200, color: 0),
        _card('j2', 'Tries it', x: 280, y: 0, width: 200),
        _card('j3', 'Gets stuck', x: 560, y: 0, width: 200, color: 3),
        _card('j4', 'Comes back', x: 840, y: 0, width: 200, color: 1),
        _card(
          'p1',
          'What they feel',
          x: 0,
          y: 180,
          width: 200,
          height: 84,
          color: 4,
        ),
        _card(
          'p2',
          'What we could do',
          x: 560,
          y: 180,
          width: 200,
          height: 84,
          color: 4,
        ),
      ],
      edges: [
        _link('j1', 'j2'),
        _link('j2', 'j3'),
        _link('j3', 'j4'),
        _link('j3', 'p2', endMarker: CanvasEdgeMarker.none),
      ],
      settings: const CanvasSettings(background: CanvasBackground.lines),
    );

CanvasDocument _swot() => CanvasDocument(
      frames: [
        _frame('s', 'Strengths', x: 0, y: 0, width: 400, height: 300, color: 1),
        _frame(
          'w',
          'Weaknesses',
          x: 440,
          y: 0,
          width: 400,
          height: 300,
          color: 3,
        ),
        _frame(
          'o',
          'Opportunities',
          x: 0,
          y: 340,
          width: 400,
          height: 300,
          color: 0,
        ),
        _frame(
          't',
          'Threats',
          x: 440,
          y: 340,
          width: 400,
          height: 300,
          color: 6,
        ),
      ],
      nodes: [
        _card(
          's1',
          'What we are good at',
          x: 24,
          y: 64,
          width: 352,
          frameId: 's',
        ),
        _card(
          'w1',
          'Where we fall short',
          x: 464,
          y: 64,
          width: 352,
          frameId: 'w',
        ),
        _card(
          'o1',
          'What is open to us',
          x: 24,
          y: 404,
          width: 352,
          frameId: 'o',
        ),
        _card(
          't1',
          'What could go wrong',
          x: 464,
          y: 404,
          width: 352,
          frameId: 't',
        ),
      ],
      settings: const CanvasSettings(background: CanvasBackground.blank),
    );

CanvasDocument _kanban() => CanvasDocument(
      frames: [
        _frame('todo', 'To do', x: 0, y: 0, width: 300, height: 520, color: 5),
        _frame(
          'doing',
          'Doing',
          x: 340,
          y: 0,
          width: 300,
          height: 520,
          color: 0,
        ),
        _frame('done', 'Done', x: 680, y: 0, width: 300, height: 520, color: 1),
      ],
      nodes: [
        _card('t1', 'First thing', x: 20, y: 60, width: 260, frameId: 'todo'),
        _card('t2', 'Second thing', x: 20, y: 176, width: 260, frameId: 'todo'),
        _card(
          'd1',
          'In progress',
          x: 360,
          y: 60,
          width: 260,
          frameId: 'doing',
          color: 0,
        ),
      ],
    );

CanvasDocument _meeting() => CanvasDocument(
      frames: [
        _frame(
          'agenda',
          'Agenda',
          x: 0,
          y: 0,
          width: 360,
          height: 420,
          color: 0,
        ),
        _frame('notes', 'Notes', x: 400, y: 0, width: 440, height: 420),
        _frame(
          'actions',
          'Actions',
          x: 880,
          y: 0,
          width: 360,
          height: 420,
          color: 1,
        ),
      ],
      nodes: [
        _card(
          'a1',
          'What we are here for',
          x: 24,
          y: 60,
          width: 312,
          frameId: 'agenda',
        ),
        _card(
          'n1',
          'What was said',
          x: 424,
          y: 60,
          width: 392,
          height: 200,
          frameId: 'notes',
        ),
        _card(
          'c1',
          'Who does what by when',
          x: 904,
          y: 60,
          width: 312,
          frameId: 'actions',
          color: 1,
        ),
      ],
      settings: const CanvasSettings(background: CanvasBackground.blank),
    );

CanvasDocument _study() => CanvasDocument(
      nodes: [
        _card(
          'topic',
          'The topic',
          x: 0,
          y: 0,
          height: 84,
          color: 0,
        ),
        _card('c1', 'Concept', x: 320, y: -140, width: 200),
        _card('c2', 'Concept', x: 320, y: -10, width: 200),
        _card('c3', 'Concept', x: 320, y: 120, width: 200),
        _card('e1', 'Worked example', x: 620, y: -10, color: 2),
        _card(
          'q1',
          'Question I still have',
          x: 620,
          y: 120,
          color: 3,
        ),
      ],
      edges: [
        _link('topic', 'c1', endMarker: CanvasEdgeMarker.none),
        _link('topic', 'c2', endMarker: CanvasEdgeMarker.none),
        _link('topic', 'c3', endMarker: CanvasEdgeMarker.none),
        _link('c2', 'e1', label: 'shown by'),
        _link('c3', 'q1', label: 'unclear'),
      ],
    );

CanvasDocument _roadmap() => CanvasDocument(
      frames: [
        _frame(
          'q1',
          'This quarter',
          x: 0,
          y: 0,
          width: 340,
          height: 420,
          color: 1,
        ),
        _frame('q2', 'Next', x: 380, y: 0, width: 340, height: 420, color: 0),
        _frame(
          'q3',
          'After that',
          x: 760,
          y: 0,
          width: 340,
          height: 420,
          color: 5,
        ),
      ],
      nodes: [
        _card(
          'r1',
          'Shipping now',
          x: 24,
          y: 60,
          width: 292,
          frameId: 'q1',
          color: 1,
        ),
        _card('r2', 'Being designed', x: 404, y: 60, width: 292, frameId: 'q2'),
        _card('r3', 'An idea', x: 784, y: 60, width: 292, frameId: 'q3'),
      ],
      edges: [
        _link('r1', 'r2'),
        _link('r2', 'r3'),
      ],
      settings: const CanvasSettings(background: CanvasBackground.lines),
    );
