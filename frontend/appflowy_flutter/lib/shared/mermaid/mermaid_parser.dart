import 'mermaid_model.dart';

/// Reads Mermaid source into a [MermaidDocument].
///
/// This is a pure, hand-written reader — there is no JavaScript engine and no
/// web view anywhere in the pipeline, so a diagram is laid out and painted by
/// Flutter itself and can wear the application's own colours.
///
/// It deliberately understands the shapes people actually write rather than
/// the whole grammar: anything it cannot read comes back as a
/// [MermaidDocument] carrying an [MermaidDocument.error], which the block
/// shows as a quiet notice beside the source.
MermaidDocument parseMermaid(String source) {
  final lines = _prepare(source);
  if (lines.isEmpty) {
    return const MermaidDocument(kind: MermaidDiagramKind.flowchart);
  }

  final header = lines.first.text;
  final kind = mermaidKindOf(header);
  final body = lines.skip(1).toList();

  try {
    switch (kind) {
      case MermaidDiagramKind.flowchart:
        return _parseFlowchart(header, body);
      case MermaidDiagramKind.sequence:
        return _parseSequence(body);
      case MermaidDiagramKind.classDiagram:
        return _parseClassDiagram(body);
      case MermaidDiagramKind.state:
        return _parseStateDiagram(header, body);
      case MermaidDiagramKind.entityRelationship:
        return _parseEntityDiagram(body);
      case MermaidDiagramKind.pie:
        return _parsePie(header, body);
      case MermaidDiagramKind.mindmap:
        return _parseMindmap(body);
      case MermaidDiagramKind.timeline:
        return _parseTimeline(body);
      case MermaidDiagramKind.journey:
        return _parseJourney(body);
      case MermaidDiagramKind.gantt:
        return _parseGantt(body);
      case MermaidDiagramKind.unsupported:
        return MermaidDocument.failed(
          'AppFlowy cannot draw "${_firstWord(header)}" diagrams yet.',
        );
    }
  } catch (error) {
    return MermaidDocument.failed(
      'This diagram could not be read: $error',
      kind: kind,
    );
  }
}

/// The diagram type named by a source's first meaningful line.
MermaidDiagramKind mermaidKindOf(String header) {
  final word = _firstWord(header).toLowerCase();
  switch (word) {
    case 'graph':
    case 'flowchart':
    case 'flowchart-elk':
      return MermaidDiagramKind.flowchart;
    case 'sequencediagram':
      return MermaidDiagramKind.sequence;
    case 'classdiagram':
    case 'classdiagram-v2':
      return MermaidDiagramKind.classDiagram;
    case 'statediagram':
    case 'statediagram-v2':
      return MermaidDiagramKind.state;
    case 'erdiagram':
      return MermaidDiagramKind.entityRelationship;
    case 'pie':
      return MermaidDiagramKind.pie;
    case 'mindmap':
      return MermaidDiagramKind.mindmap;
    case 'timeline':
      return MermaidDiagramKind.timeline;
    case 'journey':
      return MermaidDiagramKind.journey;
    case 'gantt':
      return MermaidDiagramKind.gantt;
    default:
      return MermaidDiagramKind.unsupported;
  }
}

// ---------------------------------------------------------------------------
// Source preparation
// ---------------------------------------------------------------------------

class _Line {
  _Line(this.text, this.indent);

  final String text;
  final int indent;
}

/// Strips comments and directives and splits the source into indented lines.
///
/// Indentation is kept because mind maps carry their whole structure in it.
List<_Line> _prepare(String source) {
  final out = <_Line>[];
  for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
    // `%%{init: …}%%` configures the renderer and is not content.
    var line = raw.replaceAll(RegExp(r'%%\{.*?\}%%'), '');
    final comment = line.indexOf('%%');
    if (comment >= 0) {
      line = line.substring(0, comment);
    }
    final trimmed = line.trimRight();
    if (trimmed.trim().isEmpty) {
      continue;
    }
    var indent = 0;
    for (final unit in trimmed.codeUnits) {
      if (unit == 0x20) {
        indent += 1;
      } else if (unit == 0x09) {
        indent += 4;
      } else {
        break;
      }
    }
    out.add(_Line(trimmed.trim(), indent));
  }
  return out;
}

String _firstWord(String text) {
  final match = RegExp(r'^[A-Za-z][A-Za-z0-9\-]*').firstMatch(text.trim());
  return match?.group(0) ?? '';
}

/// Splits a statement line on `;`, which Mermaid allows as a separator.
Iterable<String> _statements(String line) sync* {
  for (final part in line.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) {
      yield trimmed;
    }
  }
}

String _unquote(String text) {
  var value = text.trim();
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1);
  }
  return value.replaceAll('<br/>', '\n').replaceAll('<br>', '\n').trim();
}

// ---------------------------------------------------------------------------
// Flowchart
// ---------------------------------------------------------------------------

MermaidDirection _directionOf(String token, MermaidDirection fallback) {
  switch (token.toUpperCase()) {
    case 'TD':
    case 'TB':
      return MermaidDirection.topToBottom;
    case 'BT':
      return MermaidDirection.bottomToTop;
    case 'LR':
      return MermaidDirection.leftToRight;
    case 'RL':
      return MermaidDirection.rightToLeft;
    default:
      return fallback;
  }
}

MermaidDocument _parseFlowchart(String header, List<_Line> body) {
  final parts = header.trim().split(RegExp(r'\s+'));
  var direction = MermaidDirection.topToBottom;
  if (parts.length > 1) {
    direction = _directionOf(parts[1], direction);
  }

  final builder = _GraphBuilder(direction);
  final openSubgraphs = <String>[];
  var subgraphCount = 0;

  for (final line in body) {
    for (final statement in _statements(line.text)) {
      final lower = statement.toLowerCase();

      if (lower.startsWith('subgraph')) {
        final rest = statement.substring('subgraph'.length).trim();
        subgraphCount += 1;
        final id = 'sub$subgraphCount';
        var label = rest;
        final titled = RegExp(r'^(\S+)\s*\[(.*)\]$').firstMatch(rest);
        if (titled != null) {
          label = _unquote(titled.group(2)!);
        } else {
          label = _unquote(rest);
        }
        builder.subgraphs.add(MermaidSubgraph(id: id, label: label));
        openSubgraphs.add(id);
        continue;
      }
      if (lower == 'end') {
        if (openSubgraphs.isNotEmpty) {
          openSubgraphs.removeLast();
        }
        continue;
      }
      if (lower.startsWith('direction ')) {
        if (openSubgraphs.isEmpty) {
          builder.direction =
              _directionOf(statement.substring(10).trim(), builder.direction);
        }
        continue;
      }
      if (lower.startsWith('classdef ') ||
          lower.startsWith('style ') ||
          lower.startsWith('linkstyle ') ||
          lower.startsWith('click ')) {
        continue;
      }
      if (lower.startsWith('class ')) {
        final rest = statement.substring(6).trim().split(RegExp(r'\s+'));
        if (rest.length >= 2) {
          final accent = builder.accentFor(rest.last);
          for (final id in rest.first.split(',')) {
            builder.accents[id.trim()] = accent;
          }
        }
        continue;
      }

      builder.readChain(statement, subgraph: openSubgraphs.lastOrNull);
    }
  }

  return MermaidDocument(
    kind: MermaidDiagramKind.flowchart,
    graph: builder.build(),
  );
}

/// Accumulates nodes and edges while a chain of statements is read.
class _GraphBuilder {
  _GraphBuilder(this.direction);

  MermaidDirection direction;
  final Map<String, MermaidNode> nodes = <String, MermaidNode>{};
  final List<MermaidEdge> edges = <MermaidEdge>[];
  final List<MermaidSubgraph> subgraphs = <MermaidSubgraph>[];
  final Map<String, int> accents = <String, int>{};
  final Map<String, int> _classAccents = <String, int>{};

  int accentFor(String className) =>
      _classAccents.putIfAbsent(className, () => _classAccents.length + 1);

  void addNode(MermaidNode node) {
    final existing = nodes[node.id];
    if (existing == null) {
      nodes[node.id] = node;
      return;
    }
    // A later mention supplies the label the first one lacked.
    nodes[node.id] = existing.copyWith(
      label: node.label.isNotEmpty ? node.label : existing.label,
      shape: node.shape != MermaidNodeShape.rounded ? node.shape : null,
      subgraph: existing.subgraph ?? node.subgraph,
    );
  }

  MermaidGraph build() {
    final resolved = nodes.values
        .map(
          (node) => accents.containsKey(node.id)
              ? node.copyWith(accent: accents[node.id])
              : node,
        )
        .toList();
    return MermaidGraph(
      nodes: resolved,
      edges: edges,
      direction: direction,
      subgraphs: subgraphs,
    );
  }

  /// Reads `A[Start] --> B{Choice} -->|yes| C(End)` in one pass.
  void readChain(String statement, {String? subgraph}) {
    final scanner = _ChainScanner(statement);
    final first = scanner.readNode();
    if (first == null) {
      return;
    }
    addNode(first.copyWith(subgraph: subgraph));
    var previous = first.id;
    while (true) {
      final link = scanner.readLink();
      if (link == null) {
        break;
      }
      final next = scanner.readNode();
      if (next == null) {
        break;
      }
      addNode(next.copyWith(subgraph: subgraph));
      edges.add(
        MermaidEdge(
          from: previous,
          to: next.id,
          label: link.label,
          style: link.style,
          head: link.head,
          tail: link.tail,
        ),
      );
      previous = next.id;
    }
  }
}

class _Link {
  const _Link({
    required this.style,
    required this.head,
    required this.tail,
    required this.label,
  });

  final MermaidLineStyle style;
  final MermaidArrowHead head;
  final MermaidArrowHead tail;
  final String label;
}

/// Walks a flowchart statement, alternately reading a node and a link.
class _ChainScanner {
  _ChainScanner(this.source);

  final String source;
  int index = 0;

  static const _lineChars = '-.=~';

  static final _idPattern = RegExp(r'^[^\s\[\](){}<>|:;"]+');

  void _skipSpaces() {
    while (index < source.length && source[index] == ' ') {
      index += 1;
    }
  }

  bool get _atEnd => index >= source.length;

  MermaidNode? readNode() {
    _skipSpaces();
    if (_atEnd) {
      return null;
    }
    final rest = source.substring(index);
    final id = _idPattern.firstMatch(rest)?.group(0);
    if (id == null || id.isEmpty) {
      return null;
    }
    index += id.length;

    final shape = _readShape();
    if (shape == null) {
      return MermaidNode(id: id, label: id);
    }
    return MermaidNode(
      id: id,
      label: shape.label.isEmpty ? id : shape.label,
      shape: shape.shape,
    );
  }

  /// The wrappers a flowchart node can wear, longest opener first so `((`
  /// is never read as `(`.
  static const List<List<String>> _wrappers = [
    ['(((', ')))'],
    ['[[', ']]'],
    ['[(', ')]'],
    ['((', '))'],
    ['{{', '}}'],
    ['([', '])'],
    ['[/', '/]'],
    [r'[\', r'\]'],
    ['[', ']'],
    ['(', ')'],
    ['{', '}'],
    ['>', ']'],
  ];

  static MermaidNodeShape _shapeFor(String open, String close) {
    switch ('$open$close') {
      case '((()))':
        return MermaidNodeShape.doubleCircle;
      case '[[]]':
        return MermaidNodeShape.subroutine;
      case '[()]':
        return MermaidNodeShape.cylinder;
      case '(())':
        return MermaidNodeShape.circle;
      case '{{}}':
        return MermaidNodeShape.hexagon;
      case '([])':
        return MermaidNodeShape.stadium;
      case '[//]':
        return MermaidNodeShape.parallelogram;
      case r'[\\]':
        return MermaidNodeShape.parallelogramAlt;
      case r'[/\]':
        return MermaidNodeShape.trapezoid;
      case r'[\/]':
        return MermaidNodeShape.trapezoidAlt;
      case '[]':
        return MermaidNodeShape.rectangle;
      case '()':
        return MermaidNodeShape.rounded;
      case '{}':
        return MermaidNodeShape.diamond;
      case '>]':
        return MermaidNodeShape.asymmetric;
      default:
        return MermaidNodeShape.rounded;
    }
  }

  ({String label, MermaidNodeShape shape})? _readShape() {
    if (_atEnd) {
      return null;
    }
    for (final wrapper in _wrappers) {
      final open = wrapper[0];
      if (!source.startsWith(open, index)) {
        continue;
      }
      // `[/…\]` and `[\…/]` share their opener with the parallelograms, so
      // the closer decides which of the four it is.
      final body = _readUntilCloser(index + open.length, wrapper[1]);
      if (body == null) {
        continue;
      }
      index = body.end;
      return (
        label: _unquote(body.text),
        shape: _shapeFor(open, body.closer),
      );
    }
    return null;
  }

  ({String text, int end, String closer})? _readUntilCloser(
    int start,
    String preferred,
  ) {
    // Accept the mirrored closers too, so `[/ … \]` is a trapezoid.
    final closers = <String>{
      preferred,
      if (preferred == '/]') r'\]',
      if (preferred == r'\]') '/]',
    }.toList();
    var depth = 0;
    var quoted = false;
    for (var i = start; i < source.length; i++) {
      final char = source[i];
      if (char == '"') {
        quoted = !quoted;
        continue;
      }
      if (quoted) {
        continue;
      }
      if (char == '(' || char == '[' || char == '{') {
        depth += 1;
        continue;
      }
      for (final closer in closers) {
        if (source.startsWith(closer, i)) {
          if (depth == 0) {
            return (
              text: source.substring(start, i),
              end: i + closer.length,
              closer: closer,
            );
          }
        }
      }
      if (char == ')' || char == ']' || char == '}') {
        depth -= 1;
      }
    }
    return null;
  }

  _Link? readLink() {
    _skipSpaces();
    if (_atEnd) {
      return null;
    }
    var reversed = false;
    var start = index;
    if (source[index] == '<' &&
        index + 1 < source.length &&
        _lineChars.contains(source[index + 1])) {
      reversed = true;
      start += 1;
    }
    var cursor = start;
    while (cursor < source.length && _lineChars.contains(source[cursor])) {
      cursor += 1;
    }
    if (cursor == start) {
      return null;
    }
    final run = source.substring(start, cursor);
    if (run.length < 2 && !run.startsWith('-.')) {
      return null;
    }
    var style = MermaidLineStyle.solid;
    if (run.contains('=')) {
      style = MermaidLineStyle.thick;
    } else if (run.contains('.')) {
      style = MermaidLineStyle.dotted;
    }
    index = cursor;

    var head = MermaidArrowHead.none;
    var label = '';

    final headMatch = RegExp('^([>xo])').firstMatch(source.substring(index));
    if (headMatch != null) {
      head = _headFor(headMatch.group(1)!);
      index += 1;
    } else {
      // `-- text -->` puts the words between two runs of line characters.
      final middle = RegExp(r'^\s+([^\s][^\-=~|]*?)\s+[-.=~]+([>xo])?')
          .firstMatch(source.substring(index));
      if (middle != null) {
        label = _unquote(middle.group(1)!);
        head = middle.group(2) == null
            ? MermaidArrowHead.none
            : _headFor(middle.group(2)!);
        index += middle.group(0)!.length;
      }
    }

    // `-->|text|`
    final piped =
        RegExp(r'^\s*\|([^|]*)\|').firstMatch(source.substring(index));
    if (piped != null) {
      label = _unquote(piped.group(1)!);
      index += piped.group(0)!.length;
    }

    return _Link(
      style: style,
      head: head,
      tail: reversed ? MermaidArrowHead.arrow : MermaidArrowHead.none,
      label: label,
    );
  }

  static MermaidArrowHead _headFor(String token) {
    switch (token) {
      case '>':
        return MermaidArrowHead.arrow;
      case 'x':
        return MermaidArrowHead.cross;
      case 'o':
        return MermaidArrowHead.circle;
      default:
        return MermaidArrowHead.none;
    }
  }
}

// ---------------------------------------------------------------------------
// Sequence
// ---------------------------------------------------------------------------

final _sequenceMessage = RegExp(
  r'^([^\s:\-<>+]+)\s*(-?->>|-?->|--?\)|--?x|<<-?-?>>)\s*([^\s:]+)\s*:\s*(.*)$',
);

MermaidDocument _parseSequence(List<_Line> body) {
  final actors = <String, MermaidSequenceActor>{};
  final steps = <MermaidSequenceStep>[];

  void ensureActor(String id, {bool isActor = false}) {
    final key = id.trim();
    if (key.isEmpty) {
      return;
    }
    actors.putIfAbsent(
      key,
      () => MermaidSequenceActor(id: key, label: key, isActor: isActor),
    );
  }

  for (final line in body) {
    final statement = line.text;
    final lower = statement.toLowerCase();

    if (lower.startsWith('participant ') || lower.startsWith('actor ')) {
      final isActor = lower.startsWith('actor ');
      final rest = statement.substring(isActor ? 6 : 12).trim();
      final aliased =
          RegExp(r'^(\S+)\s+as\s+(.+)$', caseSensitive: false).firstMatch(rest);
      final id = aliased == null ? rest : aliased.group(1)!;
      final label = aliased == null ? rest : _unquote(aliased.group(2)!);
      actors[id] = MermaidSequenceActor(id: id, label: label, isActor: isActor);
      continue;
    }
    if (lower == 'autonumber' ||
        lower.startsWith('activate ') ||
        lower.startsWith('deactivate ') ||
        lower.startsWith('destroy ') ||
        lower.startsWith('box ') ||
        lower.startsWith('link ') ||
        lower.startsWith('%%')) {
      continue;
    }
    if (lower.startsWith('note ')) {
      final note = RegExp(
        r'^note\s+(left of|right of|over)\s+([^:]+):\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(statement);
      if (note != null) {
        final placement = switch (note.group(1)!.toLowerCase()) {
          'left of' => MermaidNotePlacement.leftOf,
          'right of' => MermaidNotePlacement.rightOf,
          _ => MermaidNotePlacement.over,
        };
        final targets =
            note.group(2)!.split(',').map((value) => value.trim()).toList();
        for (final target in targets) {
          ensureActor(target);
        }
        steps.add(
          MermaidSequenceStep(
            kind: MermaidSequenceStepKind.note,
            from: targets.first,
            to: targets.last,
            text: _unquote(note.group(3)!),
            placement: placement,
          ),
        );
      }
      continue;
    }
    if (RegExp(
          r'^(loop|alt|opt|par|critical|break|rect)\b',
          caseSensitive: false,
        ).hasMatch(lower) ||
        lower == 'end' ||
        RegExp(r'^(else|and|option)\b', caseSensitive: false).hasMatch(lower)) {
      if (lower == 'end') {
        steps.add(
          const MermaidSequenceStep(kind: MermaidSequenceStepKind.blockEnd),
        );
      } else if (RegExp(r'^(else|and|option)\b', caseSensitive: false)
          .hasMatch(lower)) {
        final space = statement.indexOf(' ');
        steps.add(
          MermaidSequenceStep(
            kind: MermaidSequenceStepKind.blockElse,
            keyword: space < 0 ? statement : statement.substring(0, space),
            text: space < 0 ? '' : statement.substring(space + 1).trim(),
          ),
        );
      } else {
        final space = statement.indexOf(' ');
        steps.add(
          MermaidSequenceStep(
            kind: MermaidSequenceStepKind.blockStart,
            keyword: space < 0 ? statement : statement.substring(0, space),
            text: space < 0 ? '' : statement.substring(space + 1).trim(),
          ),
        );
      }
      continue;
    }

    final message = _sequenceMessage.firstMatch(statement);
    if (message != null) {
      final from = message.group(1)!.trim();
      final arrow = message.group(2)!;
      final to = message.group(3)!.trim();
      ensureActor(from);
      ensureActor(to);
      steps.add(
        MermaidSequenceStep(
          kind: MermaidSequenceStepKind.message,
          from: from,
          to: to,
          text: _unquote(message.group(4)!),
          style: arrow.startsWith('--')
              ? MermaidLineStyle.dashed
              : MermaidLineStyle.solid,
          head: arrow.endsWith('x')
              ? MermaidArrowHead.cross
              : arrow.endsWith(')')
                  ? MermaidArrowHead.open
                  : arrow.endsWith('>>')
                      ? MermaidArrowHead.arrow
                      : MermaidArrowHead.open,
        ),
      );
    }
  }

  return MermaidDocument(
    kind: MermaidDiagramKind.sequence,
    sequence: MermaidSequence(
      actors: actors.values.toList(),
      steps: steps,
    ),
  );
}

// ---------------------------------------------------------------------------
// Class diagram
// ---------------------------------------------------------------------------

final _classRelation = RegExp(
  r'^(\S+)\s*(?:"([^"]*)"\s*)?(<\|--|--\|>|\*--|--\*|o--|--o|-->|<--|\.\.>|<\.\.|\.\.\|>|<\|\.\.|--|\.\.)\s*(?:"([^"]*)"\s*)?(\S+?)\s*(?::\s*(.*))?$',
);

MermaidDocument _parseClassDiagram(List<_Line> body) {
  final builder = _GraphBuilder(MermaidDirection.topToBottom);
  final members = <String, List<String>>{};
  String? openClass;

  void ensure(String id) {
    builder.addNode(
      MermaidNode(id: id, label: id, shape: MermaidNodeShape.record),
    );
    members.putIfAbsent(id, () => <String>[]);
  }

  for (final line in body) {
    final statement = line.text;

    if (openClass != null) {
      if (statement == '}') {
        openClass = null;
        continue;
      }
      members[openClass]!.add(_cleanMember(statement));
      continue;
    }
    if (statement.startsWith('class ')) {
      final rest = statement.substring(6).trim();
      final open = rest.endsWith('{');
      final name = (open ? rest.substring(0, rest.length - 1) : rest).trim();
      final labelled = RegExp(r'^(\S+)\s*\[(.*)\]$').firstMatch(name);
      final id = labelled == null
          ? name.split(RegExp(r'\s+')).first
          : labelled.group(1)!;
      ensure(id);
      if (labelled != null) {
        builder.nodes[id] =
            builder.nodes[id]!.copyWith(label: _unquote(labelled.group(2)!));
      }
      if (open) {
        openClass = id;
      }
      continue;
    }
    if (statement.startsWith('direction ')) {
      builder.direction =
          _directionOf(statement.substring(10).trim(), builder.direction);
      continue;
    }
    if (statement.startsWith('note') || statement.startsWith('click')) {
      continue;
    }

    final relation = _classRelation.firstMatch(statement);
    if (relation != null) {
      final left = relation.group(1)!;
      final token = relation.group(3)!;
      final right = relation.group(5)!;
      ensure(left);
      ensure(right);
      final decoration = _classArrow(token);
      builder.edges.add(
        MermaidEdge(
          from: left,
          to: right,
          label: _unquote(relation.group(6) ?? ''),
          style: token.contains('.')
              ? MermaidLineStyle.dashed
              : MermaidLineStyle.solid,
          head: decoration.head,
          tail: decoration.tail,
          fromLabel: relation.group(2) ?? '',
          toLabel: relation.group(4) ?? '',
        ),
      );
      continue;
    }

    // `Animal : +int age`
    final member = RegExp(r'^(\S+)\s*:\s*(.+)$').firstMatch(statement);
    if (member != null) {
      final id = member.group(1)!;
      ensure(id);
      members[id]!.add(_cleanMember(member.group(2)!));
    }
  }

  final nodes = builder.nodes.values
      .map((node) => node.copyWith(members: members[node.id] ?? const []))
      .toList();

  return MermaidDocument(
    kind: MermaidDiagramKind.classDiagram,
    graph: MermaidGraph(
      nodes: nodes,
      edges: builder.edges,
      direction: builder.direction,
    ),
  );
}

String _cleanMember(String raw) => raw
    .replaceAll(RegExp(r'^\s*<<.*?>>\s*'), '')
    .replaceAll(RegExp(r'\s*\$\s*$'), '')
    .trim();

({MermaidArrowHead head, MermaidArrowHead tail}) _classArrow(String token) {
  switch (token) {
    case '<|--':
      return (head: MermaidArrowHead.none, tail: MermaidArrowHead.triangle);
    case '--|>':
      return (head: MermaidArrowHead.triangle, tail: MermaidArrowHead.none);
    case '*--':
      return (
        head: MermaidArrowHead.none,
        tail: MermaidArrowHead.filledDiamond
      );
    case '--*':
      return (
        head: MermaidArrowHead.filledDiamond,
        tail: MermaidArrowHead.none
      );
    case 'o--':
      return (
        head: MermaidArrowHead.none,
        tail: MermaidArrowHead.hollowDiamond
      );
    case '--o':
      return (
        head: MermaidArrowHead.hollowDiamond,
        tail: MermaidArrowHead.none
      );
    case '-->':
    case '..>':
      return (head: MermaidArrowHead.open, tail: MermaidArrowHead.none);
    case '<--':
    case '<..':
      return (head: MermaidArrowHead.none, tail: MermaidArrowHead.open);
    case '..|>':
      return (head: MermaidArrowHead.triangle, tail: MermaidArrowHead.none);
    case '<|..':
      return (head: MermaidArrowHead.none, tail: MermaidArrowHead.triangle);
    default:
      return (head: MermaidArrowHead.none, tail: MermaidArrowHead.none);
  }
}

// ---------------------------------------------------------------------------
// State diagram
// ---------------------------------------------------------------------------

MermaidDocument _parseStateDiagram(String header, List<_Line> body) {
  final builder = _GraphBuilder(MermaidDirection.topToBottom);
  final openStates = <String>[];
  var terminalCount = 0;

  String point() {
    terminalCount += 1;
    final id = '__point$terminalCount';
    builder.addNode(
      MermaidNode(id: id, label: '', shape: MermaidNodeShape.point),
    );
    return id;
  }

  String ensure(String raw) {
    final id = raw.trim();
    if (id == '[*]') {
      return point();
    }
    builder.addNode(MermaidNode(id: id, label: id));
    return id;
  }

  for (final line in body) {
    final statement = line.text;
    final lower = statement.toLowerCase();

    if (lower.startsWith('direction ')) {
      builder.direction =
          _directionOf(statement.substring(10).trim(), builder.direction);
      continue;
    }
    if (lower == '}') {
      if (openStates.isNotEmpty) {
        openStates.removeLast();
      }
      continue;
    }
    if (lower.startsWith('note ')) {
      continue;
    }
    if (lower.startsWith('state ')) {
      final rest = statement.substring(6).trim();
      final aliased = RegExp(r'^"(.*)"\s+as\s+(\S+)$', caseSensitive: false)
          .firstMatch(rest);
      if (aliased != null) {
        builder.addNode(
          MermaidNode(
              id: aliased.group(2)!, label: _unquote(aliased.group(1)!)),
        );
        continue;
      }
      if (rest.endsWith('{')) {
        final id = rest.substring(0, rest.length - 1).trim();
        builder.subgraphs.add(MermaidSubgraph(id: id, label: _unquote(id)));
        openStates.add(id);
        continue;
      }
      builder.addNode(MermaidNode(id: rest, label: _unquote(rest)));
      continue;
    }

    final transition = RegExp(r'^(.+?)\s*-->\s*([^:]+?)\s*(?::\s*(.*))?$')
        .firstMatch(statement);
    if (transition != null) {
      final from = ensure(transition.group(1)!);
      final to = ensure(transition.group(2)!);
      if (openStates.isNotEmpty) {
        builder.nodes[from] =
            builder.nodes[from]!.copyWith(subgraph: openStates.last);
        builder.nodes[to] =
            builder.nodes[to]!.copyWith(subgraph: openStates.last);
      }
      builder.edges.add(
        MermaidEdge(
          from: from,
          to: to,
          label: _unquote(transition.group(3) ?? ''),
        ),
      );
    }
  }

  return MermaidDocument(
    kind: MermaidDiagramKind.state,
    graph: builder.build(),
  );
}

// ---------------------------------------------------------------------------
// Entity relationship
// ---------------------------------------------------------------------------

final _erRelation = RegExp(
  r'^(\S+)\s+(\|o|\|\||\}o|\}\||o\{|o\||\{o|\{\|)(--|\.\.)(o\||\|\||o\{|\|\{|\|o|\{o)\s+(\S+)\s*:\s*(.*)$',
);

MermaidDocument _parseEntityDiagram(List<_Line> body) {
  final builder = _GraphBuilder(MermaidDirection.topToBottom);
  final attributes = <String, List<String>>{};
  String? openEntity;

  void ensure(String id) {
    builder.addNode(
      MermaidNode(id: id, label: id, shape: MermaidNodeShape.record),
    );
    attributes.putIfAbsent(id, () => <String>[]);
  }

  for (final line in body) {
    final statement = line.text;
    if (openEntity != null) {
      if (statement == '}') {
        openEntity = null;
        continue;
      }
      attributes[openEntity]!.add(statement.replaceAll(RegExp(r'\s+'), ' '));
      continue;
    }
    if (statement.endsWith('{')) {
      final id = statement.substring(0, statement.length - 1).trim();
      if (!id.contains(' ')) {
        ensure(id);
        openEntity = id;
        continue;
      }
    }
    final relation = _erRelation.firstMatch(statement);
    if (relation != null) {
      final left = relation.group(1)!;
      final right = relation.group(5)!;
      ensure(left);
      ensure(right);
      builder.edges.add(
        MermaidEdge(
          from: left,
          to: right,
          label: _unquote(relation.group(6)!),
          style: relation.group(3) == '..'
              ? MermaidLineStyle.dashed
              : MermaidLineStyle.solid,
          tail: _erHead(relation.group(2)!),
          head: _erHead(relation.group(4)!),
        ),
      );
    }
  }

  final nodes = builder.nodes.values
      .map((node) => node.copyWith(members: attributes[node.id] ?? const []))
      .toList();

  return MermaidDocument(
    kind: MermaidDiagramKind.entityRelationship,
    graph: MermaidGraph(nodes: nodes, edges: builder.edges),
  );
}

MermaidArrowHead _erHead(String token) {
  switch (token) {
    case '||':
      return MermaidArrowHead.one;
    case '|o':
    case 'o|':
      return MermaidArrowHead.zeroOrOne;
    case '}|':
    case '|{':
      return MermaidArrowHead.many;
    case '}o':
    case 'o{':
      return MermaidArrowHead.zeroOrMany;
    default:
      return MermaidArrowHead.none;
  }
}

// ---------------------------------------------------------------------------
// Pie
// ---------------------------------------------------------------------------

MermaidDocument _parsePie(String header, List<_Line> body) {
  var title = '';
  var showData = header.toLowerCase().contains('showdata');
  final titled =
      RegExp(r'title\s+(.*)$', caseSensitive: false).firstMatch(header);
  if (titled != null) {
    title = _unquote(titled.group(1)!);
  }

  final slices = <MermaidPieSlice>[];
  for (final line in body) {
    final statement = line.text;
    final lower = statement.toLowerCase();
    if (lower == 'showdata') {
      showData = true;
      continue;
    }
    if (lower.startsWith('title ')) {
      title = _unquote(statement.substring(6));
      continue;
    }
    final slice = RegExp(r'^(?:"([^"]*)"|([^:]+?))\s*:\s*([0-9.]+)$')
        .firstMatch(statement);
    if (slice != null) {
      final value = double.tryParse(slice.group(3)!) ?? 0;
      slices.add(
        MermaidPieSlice(
          label: _unquote(slice.group(1) ?? slice.group(2) ?? ''),
          value: value,
        ),
      );
    }
  }

  return MermaidDocument(
    kind: MermaidDiagramKind.pie,
    title: title,
    pie: MermaidPie(slices: slices, title: title, showData: showData),
  );
}

// ---------------------------------------------------------------------------
// Mind map
// ---------------------------------------------------------------------------

class _MindDraft {
  _MindDraft(this.label, this.indent, this.shape);

  final String label;
  final int indent;
  final MermaidNodeShape shape;
  final List<_MindDraft> children = <_MindDraft>[];
}

MermaidDocument _parseMindmap(List<_Line> body) {
  final roots = <_MindDraft>[];
  final stack = <_MindDraft>[];

  for (final line in body) {
    final parsed = _mindLabel(line.text);
    if (parsed.label.isEmpty) {
      continue;
    }
    final draft = _MindDraft(parsed.label, line.indent, parsed.shape);
    while (stack.isNotEmpty && stack.last.indent >= line.indent) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      roots.add(draft);
    } else {
      stack.last.children.add(draft);
    }
    stack.add(draft);
  }

  if (roots.isEmpty) {
    return const MermaidDocument(kind: MermaidDiagramKind.mindmap);
  }
  final root = roots.length == 1
      ? roots.first
      : (_MindDraft('', -1, MermaidNodeShape.circle)..children.addAll(roots));

  MermaidMindNode convert(_MindDraft draft) => MermaidMindNode(
        label: draft.label,
        shape: draft.shape,
        children: draft.children.map(convert).toList(),
      );

  return MermaidDocument(
    kind: MermaidDiagramKind.mindmap,
    mindmap: convert(root),
  );
}

({String label, MermaidNodeShape shape}) _mindLabel(String raw) {
  var text = raw.trim();
  // `::icon(fa fa-book)` and `:::className` decorate a node; neither is drawn.
  text = text.replaceAll(RegExp(r'::icon\(.*?\)'), '').trim();
  text = text.replaceAll(RegExp(r':::\S+'), '').trim();
  if (text.isEmpty) {
    return (label: '', shape: MermaidNodeShape.rounded);
  }
  for (final wrapper in const [
    ['(((', ')))', MermaidNodeShape.doubleCircle],
    ['((', '))', MermaidNodeShape.circle],
    ['(-', '-)', MermaidNodeShape.stadium],
    ['))', '((', MermaidNodeShape.circle],
    ['{{', '}}', MermaidNodeShape.hexagon],
    ['[', ']', MermaidNodeShape.rectangle],
    ['(', ')', MermaidNodeShape.rounded],
  ]) {
    final open = wrapper[0] as String;
    final close = wrapper[1] as String;
    final index = text.indexOf(open);
    if (index >= 0 && text.endsWith(close)) {
      return (
        label: _unquote(
          text.substring(
            index + open.length,
            text.length - close.length,
          ),
        ),
        shape: wrapper[2] as MermaidNodeShape,
      );
    }
  }
  return (label: _unquote(text), shape: MermaidNodeShape.rounded);
}

// ---------------------------------------------------------------------------
// Timeline
// ---------------------------------------------------------------------------

MermaidDocument _parseTimeline(List<_Line> body) {
  var title = '';
  final sections = <MermaidTimelineSection>[];
  var current = <MermaidTimelineEntry>[];
  var currentTitle = '';

  void flush() {
    if (current.isNotEmpty || currentTitle.isNotEmpty) {
      sections.add(
        MermaidTimelineSection(title: currentTitle, entries: current),
      );
      current = <MermaidTimelineEntry>[];
    }
  }

  for (final line in body) {
    final statement = line.text;
    final lower = statement.toLowerCase();
    if (lower.startsWith('title ')) {
      title = _unquote(statement.substring(6));
      continue;
    }
    if (lower.startsWith('section ')) {
      flush();
      currentTitle = _unquote(statement.substring(8));
      continue;
    }
    final parts = statement.split(':').map((value) => value.trim()).toList();
    if (parts.isEmpty) {
      continue;
    }
    if (parts.length == 1) {
      current.add(MermaidTimelineEntry(
          period: _unquote(parts.first), events: const []));
      continue;
    }
    current.add(
      MermaidTimelineEntry(
        period: _unquote(parts.first),
        events: parts
            .skip(1)
            .map(_unquote)
            .where((value) => value.isNotEmpty)
            .toList(),
      ),
    );
  }
  flush();

  return MermaidDocument(
    kind: MermaidDiagramKind.timeline,
    title: title,
    timeline: MermaidTimeline(sections: sections, title: title),
  );
}

// ---------------------------------------------------------------------------
// Journey
// ---------------------------------------------------------------------------

MermaidDocument _parseJourney(List<_Line> body) {
  var title = '';
  final sections = <MermaidJourneySection>[];
  var tasks = <MermaidJourneyTask>[];
  var currentTitle = '';

  void flush() {
    if (tasks.isNotEmpty || currentTitle.isNotEmpty) {
      sections.add(MermaidJourneySection(title: currentTitle, tasks: tasks));
      tasks = <MermaidJourneyTask>[];
    }
  }

  for (final line in body) {
    final statement = line.text;
    final lower = statement.toLowerCase();
    if (lower.startsWith('title ')) {
      title = _unquote(statement.substring(6));
      continue;
    }
    if (lower.startsWith('section ')) {
      flush();
      currentTitle = _unquote(statement.substring(8));
      continue;
    }
    final parts = statement.split(':').map((value) => value.trim()).toList();
    if (parts.length < 2) {
      continue;
    }
    tasks.add(
      MermaidJourneyTask(
        label: _unquote(parts[0]),
        score: (int.tryParse(parts[1]) ?? 3).clamp(1, 5),
        actors: parts.length > 2
            ? parts[2]
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList()
            : const <String>[],
      ),
    );
  }
  flush();

  return MermaidDocument(
    kind: MermaidDiagramKind.journey,
    title: title,
    journey: MermaidJourney(sections: sections, title: title),
  );
}

// ---------------------------------------------------------------------------
// Gantt
// ---------------------------------------------------------------------------

MermaidDocument _parseGantt(List<_Line> body) {
  var title = '';
  final sections = <MermaidGanttSection>[];
  var tasks = <MermaidGanttTask>[];
  var currentTitle = '';
  DateTime? cursor;
  final ends = <String, DateTime>{};

  void flush() {
    if (tasks.isNotEmpty || currentTitle.isNotEmpty) {
      sections.add(MermaidGanttSection(title: currentTitle, tasks: tasks));
      tasks = <MermaidGanttTask>[];
    }
  }

  for (final line in body) {
    final statement = line.text;
    final lower = statement.toLowerCase();
    if (lower.startsWith('title ')) {
      title = _unquote(statement.substring(6));
      continue;
    }
    if (lower.startsWith('dateformat') ||
        lower.startsWith('axisformat') ||
        lower.startsWith('excludes') ||
        lower.startsWith('todaymarker') ||
        lower.startsWith('tickinterval') ||
        lower.startsWith('weekday')) {
      continue;
    }
    if (lower.startsWith('section ')) {
      flush();
      currentTitle = _unquote(statement.substring(8));
      continue;
    }
    final colon = statement.indexOf(':');
    if (colon < 0) {
      continue;
    }
    final label = _unquote(statement.substring(0, colon));
    final fields = statement
        .substring(colon + 1)
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    var done = false;
    var active = false;
    var milestone = false;
    final values = <String>[];
    for (final field in fields) {
      switch (field.toLowerCase()) {
        case 'done':
          done = true;
        case 'active':
          active = true;
        case 'crit':
          active = true;
        case 'milestone':
          milestone = true;
        default:
          values.add(field);
      }
    }

    DateTime? start;
    DateTime? end;
    final positional = values.where((value) => !_looksLikeId(value)).toList();
    if (positional.isNotEmpty) {
      start = _ganttDate(positional.first, cursor, ends);
    }
    start ??= cursor ?? DateTime(2024);
    if (positional.length > 1) {
      end = _ganttDate(positional[1], start, ends) ??
          _ganttOffset(start, positional[1]);
    }
    end ??= milestone ? start : start.add(const Duration(days: 1));
    if (end.isBefore(start)) {
      end = start;
    }
    cursor = end;
    for (final value in values.where(_looksLikeId)) {
      ends[value] = end;
    }

    tasks.add(
      MermaidGanttTask(
        label: label,
        start: start,
        end: end,
        done: done,
        active: active,
        milestone: milestone,
      ),
    );
  }
  flush();

  return MermaidDocument(
    kind: MermaidDiagramKind.gantt,
    title: title,
    gantt: MermaidGantt(sections: sections, title: title),
  );
}

bool _looksLikeId(String value) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value) &&
    !value.toLowerCase().startsWith('after');

DateTime? _ganttDate(
  String value,
  DateTime? cursor,
  Map<String, DateTime> ends,
) {
  final iso = DateTime.tryParse(value);
  if (iso != null) {
    return iso;
  }
  if (value.toLowerCase().startsWith('after ')) {
    final id = value.substring(6).trim();
    return ends[id] ?? cursor;
  }
  return null;
}

DateTime? _ganttOffset(DateTime start, String value) {
  final match = RegExp(r'^(\d+)\s*([dwhm])$', caseSensitive: false)
      .firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final amount = int.parse(match.group(1)!);
  switch (match.group(2)!.toLowerCase()) {
    case 'w':
      return start.add(Duration(days: amount * 7));
    case 'h':
      return start.add(Duration(hours: amount));
    case 'm':
      return start.add(Duration(minutes: amount));
    default:
      return start.add(Duration(days: amount));
  }
}
