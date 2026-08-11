import 'package:flutter/foundation.dart';

/// The kinds of Mermaid diagram this renderer understands.
///
/// Anything outside the list is still accepted by the block — it keeps the
/// source and says plainly that it cannot draw it yet, rather than pretending.
enum MermaidDiagramKind {
  flowchart,
  sequence,
  classDiagram,
  state,
  entityRelationship,
  pie,
  mindmap,
  timeline,
  journey,
  gantt,
  unsupported,
}

extension MermaidDiagramKindX on MermaidDiagramKind {
  /// Whether the diagram is laid out as a directed graph of boxes.
  ///
  /// Flowcharts, class, state and entity diagrams differ only in what a box
  /// and a line look like, so they share one layout pass.
  bool get isGraph =>
      this == MermaidDiagramKind.flowchart ||
      this == MermaidDiagramKind.classDiagram ||
      this == MermaidDiagramKind.state ||
      this == MermaidDiagramKind.entityRelationship;
}

/// Which way a graph grows.
enum MermaidDirection { topToBottom, bottomToTop, leftToRight, rightToLeft }

extension MermaidDirectionX on MermaidDirection {
  bool get isVertical =>
      this == MermaidDirection.topToBottom ||
      this == MermaidDirection.bottomToTop;

  bool get isReversed =>
      this == MermaidDirection.bottomToTop ||
      this == MermaidDirection.rightToLeft;
}

/// The outline a graph node is drawn with.
enum MermaidNodeShape {
  rectangle,
  rounded,
  stadium,
  circle,
  doubleCircle,
  diamond,
  hexagon,
  subroutine,
  cylinder,
  parallelogram,
  parallelogramAlt,
  trapezoid,
  trapezoidAlt,
  asymmetric,

  /// A compartment box: a title band above a list of members. Used by class
  /// and entity diagrams.
  record,

  /// The filled dot a state diagram starts and ends on.
  point,
}

/// How the two ends of an edge are decorated.
enum MermaidArrowHead {
  none,
  arrow,
  open,
  cross,
  circle,

  /// The hollow triangle of an inheritance relation.
  triangle,

  /// The filled diamond of a composition relation.
  filledDiamond,

  /// The hollow diamond of an aggregation relation.
  hollowDiamond,

  /// Crow's foot — "many" in an entity relationship.
  many,

  /// A single bar — "one" in an entity relationship.
  one,

  /// A circle and a bar — "zero or one".
  zeroOrOne,

  /// A circle and a crow's foot — "zero or many".
  zeroOrMany,
}

enum MermaidLineStyle { solid, dashed, thick, dotted }

@immutable
class MermaidNode {
  const MermaidNode({
    required this.id,
    required this.label,
    this.shape = MermaidNodeShape.rounded,
    this.members = const <String>[],
    this.subgraph,
    this.accent,
    this.note = false,
  });

  final String id;

  /// The words drawn inside the box. May contain `\n`.
  final String label;
  final MermaidNodeShape shape;

  /// The rows drawn under the title of a [MermaidNodeShape.record].
  final List<String> members;

  /// The id of the container this node belongs to, when the source declared
  /// a `subgraph`.
  final String? subgraph;

  /// A palette index chosen by `classDef`/`class`, or null to follow the
  /// diagram's own accent.
  final int? accent;

  /// Drawn as a note rather than a node — a soft, dog-eared card.
  final bool note;

  MermaidNode copyWith({
    String? label,
    MermaidNodeShape? shape,
    List<String>? members,
    String? subgraph,
    int? accent,
  }) =>
      MermaidNode(
        id: id,
        label: label ?? this.label,
        shape: shape ?? this.shape,
        members: members ?? this.members,
        subgraph: subgraph ?? this.subgraph,
        accent: accent ?? this.accent,
        note: note,
      );
}

@immutable
class MermaidEdge {
  const MermaidEdge({
    required this.from,
    required this.to,
    this.label = '',
    this.style = MermaidLineStyle.solid,
    this.head = MermaidArrowHead.arrow,
    this.tail = MermaidArrowHead.none,
    this.fromLabel = '',
    this.toLabel = '',
  });

  final String from;
  final String to;
  final String label;
  final MermaidLineStyle style;

  /// The decoration at the [to] end.
  final MermaidArrowHead head;

  /// The decoration at the [from] end.
  final MermaidArrowHead tail;

  /// Cardinality text drawn beside each end, used by entity diagrams.
  final String fromLabel;
  final String toLabel;
}

@immutable
class MermaidSubgraph {
  const MermaidSubgraph({required this.id, required this.label});

  final String id;
  final String label;
}

/// A directed graph — the shared shape of flowchart, class, state and entity
/// diagrams.
@immutable
class MermaidGraph {
  const MermaidGraph({
    required this.nodes,
    required this.edges,
    this.direction = MermaidDirection.topToBottom,
    this.subgraphs = const <MermaidSubgraph>[],
  });

  final List<MermaidNode> nodes;
  final List<MermaidEdge> edges;
  final MermaidDirection direction;
  final List<MermaidSubgraph> subgraphs;
}

// ---------------------------------------------------------------------------
// Sequence
// ---------------------------------------------------------------------------

enum MermaidSequenceStepKind { message, note, blockStart, blockElse, blockEnd }

@immutable
class MermaidSequenceStep {
  const MermaidSequenceStep({
    required this.kind,
    this.from = '',
    this.to = '',
    this.text = '',
    this.style = MermaidLineStyle.solid,
    this.head = MermaidArrowHead.arrow,
    this.placement = MermaidNotePlacement.over,
    this.keyword = '',
  });

  final MermaidSequenceStepKind kind;
  final String from;
  final String to;
  final String text;
  final MermaidLineStyle style;
  final MermaidArrowHead head;
  final MermaidNotePlacement placement;

  /// `loop`, `alt`, `opt`, `par`, `critical`… for a block step.
  final String keyword;
}

enum MermaidNotePlacement { leftOf, rightOf, over }

@immutable
class MermaidSequenceActor {
  const MermaidSequenceActor({
    required this.id,
    required this.label,
    this.isActor = false,
  });

  final String id;
  final String label;

  /// Drawn as a stick figure rather than a box.
  final bool isActor;
}

@immutable
class MermaidSequence {
  const MermaidSequence({required this.actors, required this.steps});

  final List<MermaidSequenceActor> actors;
  final List<MermaidSequenceStep> steps;
}

// ---------------------------------------------------------------------------
// Pie
// ---------------------------------------------------------------------------

@immutable
class MermaidPieSlice {
  const MermaidPieSlice({required this.label, required this.value});

  final String label;
  final double value;
}

@immutable
class MermaidPie {
  const MermaidPie({
    required this.slices,
    this.title = '',
    this.showData = false,
  });

  final List<MermaidPieSlice> slices;
  final String title;
  final bool showData;

  double get total => slices.fold(0, (sum, slice) => sum + slice.value);
}

// ---------------------------------------------------------------------------
// Mind map
// ---------------------------------------------------------------------------

@immutable
class MermaidMindNode {
  const MermaidMindNode({
    required this.label,
    required this.children,
    this.shape = MermaidNodeShape.rounded,
  });

  final String label;
  final List<MermaidMindNode> children;
  final MermaidNodeShape shape;
}

// ---------------------------------------------------------------------------
// Timeline & journey
// ---------------------------------------------------------------------------

@immutable
class MermaidTimelineEntry {
  const MermaidTimelineEntry({required this.period, required this.events});

  final String period;
  final List<String> events;
}

@immutable
class MermaidTimelineSection {
  const MermaidTimelineSection({required this.title, required this.entries});

  final String title;
  final List<MermaidTimelineEntry> entries;
}

@immutable
class MermaidTimeline {
  const MermaidTimeline({required this.sections, this.title = ''});

  final List<MermaidTimelineSection> sections;
  final String title;
}

@immutable
class MermaidJourneyTask {
  const MermaidJourneyTask({
    required this.label,
    required this.score,
    required this.actors,
  });

  final String label;

  /// 1..5, where 5 is delighted.
  final int score;
  final List<String> actors;
}

@immutable
class MermaidJourneySection {
  const MermaidJourneySection({required this.title, required this.tasks});

  final String title;
  final List<MermaidJourneyTask> tasks;
}

@immutable
class MermaidJourney {
  const MermaidJourney({required this.sections, this.title = ''});

  final List<MermaidJourneySection> sections;
  final String title;
}

// ---------------------------------------------------------------------------
// Gantt
// ---------------------------------------------------------------------------

@immutable
class MermaidGanttTask {
  const MermaidGanttTask({
    required this.label,
    required this.start,
    required this.end,
    this.done = false,
    this.active = false,
    this.milestone = false,
  });

  final String label;
  final DateTime start;
  final DateTime end;
  final bool done;
  final bool active;
  final bool milestone;
}

@immutable
class MermaidGanttSection {
  const MermaidGanttSection({required this.title, required this.tasks});

  final String title;
  final List<MermaidGanttTask> tasks;
}

@immutable
class MermaidGantt {
  const MermaidGantt({required this.sections, this.title = ''});

  final List<MermaidGanttSection> sections;
  final String title;

  DateTime? get earliest {
    DateTime? found;
    for (final section in sections) {
      for (final task in section.tasks) {
        if (found == null || task.start.isBefore(found)) {
          found = task.start;
        }
      }
    }
    return found;
  }

  DateTime? get latest {
    DateTime? found;
    for (final section in sections) {
      for (final task in section.tasks) {
        if (found == null || task.end.isAfter(found)) {
          found = task.end;
        }
      }
    }
    return found;
  }
}

// ---------------------------------------------------------------------------
// The parsed document
// ---------------------------------------------------------------------------

/// What a piece of Mermaid source turned into.
///
/// Exactly one of the payload fields is set, chosen by [kind]. A source that
/// could not be read keeps [error] and is drawn as a quiet notice instead of
/// an empty frame.
@immutable
class MermaidDocument {
  const MermaidDocument({
    required this.kind,
    this.title = '',
    this.graph,
    this.sequence,
    this.pie,
    this.mindmap,
    this.timeline,
    this.journey,
    this.gantt,
    this.error,
  });

  const MermaidDocument.failed(this.error,
      {this.kind = MermaidDiagramKind.unsupported})
      : title = '',
        graph = null,
        sequence = null,
        pie = null,
        mindmap = null,
        timeline = null,
        journey = null,
        gantt = null;

  final MermaidDiagramKind kind;
  final String title;
  final MermaidGraph? graph;
  final MermaidSequence? sequence;
  final MermaidPie? pie;
  final MermaidMindNode? mindmap;
  final MermaidTimeline? timeline;
  final MermaidJourney? journey;
  final MermaidGantt? gantt;

  /// A short sentence naming what could not be read, or null when the source
  /// was understood.
  final String? error;

  bool get isEmpty =>
      error == null &&
      (graph?.nodes.isEmpty ?? true) &&
      sequence == null &&
      pie == null &&
      mindmap == null &&
      timeline == null &&
      journey == null &&
      gantt == null;
}
