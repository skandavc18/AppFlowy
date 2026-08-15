import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

/// The document a canvas is. Pure Dart: no Flutter widgets, no backend, no
/// knowledge of how any of it is drawn.
///
/// A canvas is deliberately independent of pages and databases. It *points* at
/// them — a node carries a view id — but it never owns them, so a canvas can
/// exist in a workspace that has neither.

/// Ids are stable for the life of an object, because a future collaborator has
/// to be able to name the same card this one is moving.
String newCanvasId([String prefix = 'n']) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final noise = _random.nextInt(0x3ffff);
  return '$prefix${now.toRadixString(36)}${noise.toRadixString(36)}';
}

final math.Random _random = math.Random();

/// What a card holds.
enum CanvasNodeKind {
  /// Rich-ish text: the card somebody makes by double clicking the canvas.
  text('text'),

  /// An AppFlowy page, shown by icon, title and an optional preview.
  page('page'),

  /// A database, collection or one of its views.
  database('database'),

  /// A workspace file — pdf, document, spreadsheet, anything with a viewer.
  file('file'),

  /// A live web embed where one is possible.
  web('web'),

  /// Another canvas, nested inside this one.
  canvas('canvas'),

  /// A saved link: address, title, favicon, preview.
  bookmark('bookmark'),

  /// A picture, freely placed and sized.
  image('image'),

  /// Source code with syntax highlighting.
  code('code'),

  /// Mermaid, a mind map, or another drawn figure.
  diagram('diagram');

  const CanvasNodeKind(this.id);

  final String id;

  static CanvasNodeKind fromId(String? id) => values.firstWhere(
        (kind) => kind.id == id,
        orElse: () => CanvasNodeKind.text,
      );

  /// Whether the card points at something that lives elsewhere in the
  /// workspace, rather than owning its own content.
  bool get referencesWorkspaceObject =>
      this == page || this == database || this == canvas || this == file;

  /// Whether the card's body is worth reading at a glance, so it should be
  /// searched and outlined.
  bool get carriesText => this == text || this == code || this == diagram;
}

/// A diagram card is one of two quite different things, so which one has to be
/// chosen before the card can draw anything.
enum CanvasDiagramKind {
  /// Mermaid: a diagram written as text and laid out for you.
  mermaid('mermaid'),

  /// Excalidraw: a drawing made by hand.
  drawing('drawing');

  const CanvasDiagramKind(this.id);

  final String id;

  static CanvasDiagramKind? fromId(String? id) {
    for (final kind in values) {
      if (kind.id == id) {
        return kind;
      }
    }
    return null;
  }
}

/// The key a diagram card records its flavour under.
const String canvasDiagramKindKey = 'diagram';

/// The key a code card records its language under.
const String canvasCodeLanguageKey = 'language';

/// Which edge of a card a connection leaves from.
enum CanvasSide {
  auto('auto'),
  top('top'),
  right('right'),
  bottom('bottom'),
  left('left');

  const CanvasSide(this.id);

  final String id;

  static CanvasSide fromId(String? id) => values.firstWhere(
        (side) => side.id == id,
        orElse: () => CanvasSide.auto,
      );
}

/// How a connection is drawn.
enum CanvasEdgeStyle {
  solid('solid'),
  dashed('dashed'),
  dotted('dotted');

  const CanvasEdgeStyle(this.id);

  final String id;

  static CanvasEdgeStyle fromId(String? id) => values.firstWhere(
        (style) => style.id == id,
        orElse: () => CanvasEdgeStyle.solid,
      );
}

/// What sits at either end of a connection.
enum CanvasEdgeMarker {
  none('none'),
  arrow('arrow'),
  dot('dot');

  const CanvasEdgeMarker(this.id);

  final String id;

  static CanvasEdgeMarker fromId(String? id, CanvasEdgeMarker fallback) =>
      values.firstWhere((marker) => marker.id == id, orElse: () => fallback);
}

/// What the canvas is drawn on.
enum CanvasBackground {
  blank('blank'),
  dots('dots'),
  grid('grid'),
  lines('lines');

  const CanvasBackground(this.id);

  final String id;

  static CanvasBackground fromId(String? id) => values.firstWhere(
        (background) => background.id == id,
        orElse: () => CanvasBackground.dots,
      );
}

/// A canvas may wear its own appearance rather than the application's.
enum CanvasTheme {
  /// Follow the application, including paper mode.
  auto('auto'),
  paper('paper'),
  dark('dark'),
  blueprint('blueprint'),
  minimal('minimal');

  const CanvasTheme(this.id);

  final String id;

  static CanvasTheme fromId(String? id) => values.firstWhere(
        (theme) => theme.id == id,
        orElse: () => CanvasTheme.auto,
      );
}

/// What a freehand stroke was drawn with.
enum CanvasStrokeTool {
  pen('pen'),
  highlighter('highlighter');

  const CanvasStrokeTool(this.id);

  final String id;

  static CanvasStrokeTool fromId(String? id) => values.firstWhere(
        (tool) => tool.id == id,
        orElse: () => CanvasStrokeTool.pen,
      );
}

/// The smallest a card may be dragged to, in scene units.
const double minimumCanvasNodeWidth = 96;
const double minimumCanvasNodeHeight = 56;
const double minimumCanvasFrameWidth = 160;
const double minimumCanvasFrameHeight = 120;

/// The size a new card of each kind is created at.
Size defaultCanvasNodeSize(CanvasNodeKind kind) => switch (kind) {
      CanvasNodeKind.text => const Size(260, 120),
      CanvasNodeKind.page => const Size(280, 96),
      CanvasNodeKind.database => const Size(420, 300),
      CanvasNodeKind.file => const Size(320, 220),
      CanvasNodeKind.web => const Size(400, 280),
      CanvasNodeKind.canvas => const Size(340, 240),
      CanvasNodeKind.bookmark => const Size(300, 168),
      CanvasNodeKind.image => const Size(420, 300),
      CanvasNodeKind.code => const Size(380, 200),
      CanvasNodeKind.diagram => const Size(440, 320),
    };

/// How large a picture is allowed to make its own card when it is first put
/// down. Past this it is scaled to fit and can still be resized by hand.
const Size maximumCanvasImageSize = Size(620, 520);

/// The box a picture of [natural] pixels should be shown at.
///
/// A photograph dropped on a canvas should arrive at the shape it actually is,
/// not squeezed into whatever box the card happened to be created with.
Size canvasImageSizeFor(Size natural) {
  if (natural.width < 1 || natural.height < 1) {
    return defaultCanvasNodeSize(CanvasNodeKind.image);
  }
  final scale = math.min(
    1.0,
    math.min(
      maximumCanvasImageSize.width / natural.width,
      maximumCanvasImageSize.height / natural.height,
    ),
  );
  return Size(
    math.max(minimumCanvasNodeWidth, natural.width * scale),
    math.max(minimumCanvasNodeHeight, natural.height * scale),
  );
}

/// One card on the canvas.
@immutable
class CanvasNode {
  const CanvasNode({
    required this.id,
    required this.kind,
    required this.position,
    required this.size,
    this.title = '',
    this.text = '',
    this.url = '',
    this.reference = '',
    this.frameId,
    this.color,
    this.locked = false,
    this.data = const <String, Object?>{},
  });

  factory CanvasNode.create({
    required CanvasNodeKind kind,
    required Offset position,
    Size? size,
    String? id,
    String title = '',
    String text = '',
    String url = '',
    String reference = '',
    String? frameId,
    int? color,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    return CanvasNode(
      id: id ?? newCanvasId(),
      kind: kind,
      position: position,
      size: size ?? defaultCanvasNodeSize(kind),
      title: title,
      text: text,
      url: url,
      reference: reference,
      frameId: frameId,
      color: color,
      data: data,
    );
  }

  final String id;
  final CanvasNodeKind kind;
  final Offset position;
  final Size size;

  /// What the card is called. A page card falls back to the page's own name,
  /// so an empty title is normal and is not a missing value.
  final String title;

  /// The card's own words — the text of a text card, the source of a code or
  /// diagram card.
  final String text;

  /// An address, for a web, bookmark, image or externally hosted file card.
  final String url;

  /// The id of the workspace object this card stands for.
  final String reference;

  /// The frame this card belongs to, if any.
  final String? frameId;

  /// An index into the canvas accent set. Null means "no colour of its own".
  final int? color;

  /// A locked card cannot be moved or resized, only read.
  final bool locked;

  /// Everything a particular kind needs and no other kind understands.
  final Map<String, Object?> data;

  Rect get rect => position & size;
  Offset get center => rect.center;

  String? stringData(String key) {
    final value = data[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  bool boolData(String key, {bool fallback = false}) {
    final value = data[key];
    return value is bool ? value : fallback;
  }

  /// Which sort of diagram this is, for a diagram card that has been told.
  CanvasDiagramKind? get diagramKind => kind == CanvasNodeKind.diagram
      ? CanvasDiagramKind.fromId(stringData(canvasDiagramKindKey))
      : null;

  /// Whether the card has nothing to show yet and is waiting to be told what
  /// it holds. Clicking one of these opens the picker, because there is
  /// nothing else somebody could mean by clicking it.
  bool get needsSetUp => switch (kind) {
        CanvasNodeKind.image ||
        CanvasNodeKind.web ||
        CanvasNodeKind.bookmark =>
          url.trim().isEmpty,
        CanvasNodeKind.page ||
        CanvasNodeKind.database ||
        CanvasNodeKind.canvas ||
        CanvasNodeKind.file =>
          reference.isEmpty,
        CanvasNodeKind.diagram => diagramKind == null,
        CanvasNodeKind.text || CanvasNodeKind.code => false,
      };

  /// Whether typing into the card is what opening it means. A hand-drawn
  /// diagram is a diagram card that is emphatically NOT this.
  bool get typesItsOwnText =>
      kind == CanvasNodeKind.text ||
      kind == CanvasNodeKind.code ||
      diagramKind == CanvasDiagramKind.mermaid;

  CanvasNode copyWith({
    CanvasNodeKind? kind,
    Offset? position,
    Size? size,
    String? title,
    String? text,
    String? url,
    String? reference,
    Object? frameId = _unset,
    Object? color = _unset,
    bool? locked,
    Map<String, Object?>? data,
  }) {
    return CanvasNode(
      id: id,
      kind: kind ?? this.kind,
      position: position ?? this.position,
      size: size ?? this.size,
      title: title ?? this.title,
      text: text ?? this.text,
      url: url ?? this.url,
      reference: reference ?? this.reference,
      frameId: frameId == _unset ? this.frameId : frameId as String?,
      color: color == _unset ? this.color : color as int?,
      locked: locked ?? this.locked,
      data: data ?? this.data,
    );
  }

  CanvasNode withData(String key, Object? value) {
    final next = Map<String, Object?>.from(data);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return copyWith(data: next);
  }

  /// The card, moved and resized so it cannot be smaller than it can draw.
  CanvasNode placedAt(Offset position, Size size) => copyWith(
        position: position,
        size: Size(
          math.max(minimumCanvasNodeWidth, size.width),
          math.max(minimumCanvasNodeHeight, size.height),
        ),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.id,
        'x': position.dx,
        'y': position.dy,
        'w': size.width,
        'h': size.height,
        if (title.isNotEmpty) 'title': title,
        if (text.isNotEmpty) 'text': text,
        if (url.isNotEmpty) 'url': url,
        if (reference.isNotEmpty) 'ref': reference,
        if (frameId != null) 'frame': frameId,
        if (color != null) 'color': color,
        if (locked) 'locked': true,
        if (data.isNotEmpty) 'data': data,
      };

  static CanvasNode? fromJson(Map<String, Object?> values) {
    final id = values['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    return CanvasNode(
      id: id,
      kind: CanvasNodeKind.fromId(values['kind'] as String?),
      position: Offset(
        _readDouble(values['x']) ?? 0,
        _readDouble(values['y']) ?? 0,
      ),
      size: Size(
        math.max(minimumCanvasNodeWidth, _readDouble(values['w']) ?? 260),
        math.max(minimumCanvasNodeHeight, _readDouble(values['h']) ?? 120),
      ),
      title: values['title'] as String? ?? '',
      text: values['text'] as String? ?? '',
      url: values['url'] as String? ?? '',
      reference: values['ref'] as String? ?? '',
      frameId: values['frame'] as String?,
      color: values['color'] is int ? values['color']! as int : null,
      locked: values['locked'] == true,
      data: values['data'] is Map
          ? Map<String, Object?>.from(values['data']! as Map)
          : const <String, Object?>{},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasNode &&
      other.id == id &&
      other.kind == kind &&
      other.position == position &&
      other.size == size &&
      other.title == title &&
      other.text == text &&
      other.url == url &&
      other.reference == reference &&
      other.frameId == frameId &&
      other.color == color &&
      other.locked == locked &&
      mapEquals(other.data, data);

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        position,
        size,
        title,
        text,
        url,
        reference,
        frameId,
        color,
        locked,
        data.length,
      );
}

/// A line drawn between two cards.
@immutable
class CanvasEdge {
  const CanvasEdge({
    required this.id,
    required this.from,
    required this.to,
    this.fromSide = CanvasSide.auto,
    this.toSide = CanvasSide.auto,
    this.label = '',
    this.color,
    this.style = CanvasEdgeStyle.solid,
    this.startMarker = CanvasEdgeMarker.none,
    this.endMarker = CanvasEdgeMarker.arrow,
    this.relation = '',
  });

  factory CanvasEdge.create({
    required String from,
    required String to,
    String? id,
    CanvasSide fromSide = CanvasSide.auto,
    CanvasSide toSide = CanvasSide.auto,
    String label = '',
    int? color,
    CanvasEdgeStyle style = CanvasEdgeStyle.solid,
    CanvasEdgeMarker startMarker = CanvasEdgeMarker.none,
    CanvasEdgeMarker endMarker = CanvasEdgeMarker.arrow,
    String relation = '',
  }) =>
      CanvasEdge(
        id: id ?? newCanvasId('e'),
        from: from,
        to: to,
        fromSide: fromSide,
        toSide: toSide,
        label: label,
        color: color,
        style: style,
        startMarker: startMarker,
        endMarker: endMarker,
        relation: relation,
      );

  final String id;
  final String from;
  final String to;
  final CanvasSide fromSide;
  final CanvasSide toSide;
  final String label;
  final int? color;
  final CanvasEdgeStyle style;
  final CanvasEdgeMarker startMarker;
  final CanvasEdgeMarker endMarker;

  /// Optionally, what the line actually means — "depends on", "related to".
  /// Kept beside the label so a rename does not lose the relationship.
  final String relation;

  bool get isDirected =>
      startMarker != CanvasEdgeMarker.none ||
      endMarker != CanvasEdgeMarker.none;

  bool touches(String nodeId) => from == nodeId || to == nodeId;

  CanvasEdge copyWith({
    String? from,
    String? to,
    CanvasSide? fromSide,
    CanvasSide? toSide,
    String? label,
    Object? color = _unset,
    CanvasEdgeStyle? style,
    CanvasEdgeMarker? startMarker,
    CanvasEdgeMarker? endMarker,
    String? relation,
  }) =>
      CanvasEdge(
        id: id,
        from: from ?? this.from,
        to: to ?? this.to,
        fromSide: fromSide ?? this.fromSide,
        toSide: toSide ?? this.toSide,
        label: label ?? this.label,
        color: color == _unset ? this.color : color as int?,
        style: style ?? this.style,
        startMarker: startMarker ?? this.startMarker,
        endMarker: endMarker ?? this.endMarker,
        relation: relation ?? this.relation,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        if (fromSide != CanvasSide.auto) 'fromSide': fromSide.id,
        if (toSide != CanvasSide.auto) 'toSide': toSide.id,
        if (label.isNotEmpty) 'label': label,
        if (color != null) 'color': color,
        if (style != CanvasEdgeStyle.solid) 'style': style.id,
        if (startMarker != CanvasEdgeMarker.none) 'start': startMarker.id,
        if (endMarker != CanvasEdgeMarker.arrow) 'end': endMarker.id,
        if (relation.isNotEmpty) 'relation': relation,
      };

  static CanvasEdge? fromJson(Map<String, Object?> values) {
    final id = values['id'];
    final from = values['from'];
    final to = values['to'];
    if (id is! String || from is! String || to is! String) {
      return null;
    }
    if (id.isEmpty || from.isEmpty || to.isEmpty || from == to) {
      return null;
    }
    return CanvasEdge(
      id: id,
      from: from,
      to: to,
      fromSide: CanvasSide.fromId(values['fromSide'] as String?),
      toSide: CanvasSide.fromId(values['toSide'] as String?),
      label: values['label'] as String? ?? '',
      color: values['color'] is int ? values['color']! as int : null,
      style: CanvasEdgeStyle.fromId(values['style'] as String?),
      startMarker: CanvasEdgeMarker.fromId(
        values['start'] as String?,
        CanvasEdgeMarker.none,
      ),
      endMarker: CanvasEdgeMarker.fromId(
        values['end'] as String?,
        CanvasEdgeMarker.arrow,
      ),
      relation: values['relation'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasEdge &&
      other.id == id &&
      other.from == from &&
      other.to == to &&
      other.fromSide == fromSide &&
      other.toSide == toSide &&
      other.label == label &&
      other.color == color &&
      other.style == style &&
      other.startMarker == startMarker &&
      other.endMarker == endMarker &&
      other.relation == relation;

  @override
  int get hashCode => Object.hash(
        id,
        from,
        to,
        fromSide,
        toSide,
        label,
        color,
        style,
        startMarker,
        endMarker,
        relation,
      );
}

/// A titled container that gathers related cards.
@immutable
class CanvasFrame {
  const CanvasFrame({
    required this.id,
    required this.position,
    required this.size,
    this.title = '',
    this.description = '',
    this.color,
    this.collapsed = false,
    this.parentId,
  });

  factory CanvasFrame.create({
    required Offset position,
    required Size size,
    String? id,
    String title = '',
    String description = '',
    int? color,
    String? parentId,
  }) =>
      CanvasFrame(
        id: id ?? newCanvasId('f'),
        position: position,
        size: size,
        title: title,
        description: description,
        color: color,
        parentId: parentId,
      );

  final String id;
  final Offset position;
  final Size size;
  final String title;
  final String description;
  final int? color;
  final bool collapsed;

  /// Frames nest, so a project can be organised the way it is thought about.
  final String? parentId;

  Rect get rect => position & size;

  CanvasFrame copyWith({
    Offset? position,
    Size? size,
    String? title,
    String? description,
    Object? color = _unset,
    bool? collapsed,
    Object? parentId = _unset,
  }) =>
      CanvasFrame(
        id: id,
        position: position ?? this.position,
        size: size ?? this.size,
        title: title ?? this.title,
        description: description ?? this.description,
        color: color == _unset ? this.color : color as int?,
        collapsed: collapsed ?? this.collapsed,
        parentId: parentId == _unset ? this.parentId : parentId as String?,
      );

  CanvasFrame placedAt(Offset position, Size size) => copyWith(
        position: position,
        size: Size(
          math.max(minimumCanvasFrameWidth, size.width),
          math.max(minimumCanvasFrameHeight, size.height),
        ),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'w': size.width,
        'h': size.height,
        if (title.isNotEmpty) 'title': title,
        if (description.isNotEmpty) 'description': description,
        if (color != null) 'color': color,
        if (collapsed) 'collapsed': true,
        if (parentId != null) 'parent': parentId,
      };

  static CanvasFrame? fromJson(Map<String, Object?> values) {
    final id = values['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    return CanvasFrame(
      id: id,
      position: Offset(
        _readDouble(values['x']) ?? 0,
        _readDouble(values['y']) ?? 0,
      ),
      size: Size(
        math.max(minimumCanvasFrameWidth, _readDouble(values['w']) ?? 400),
        math.max(minimumCanvasFrameHeight, _readDouble(values['h']) ?? 300),
      ),
      title: values['title'] as String? ?? '',
      description: values['description'] as String? ?? '',
      color: values['color'] is int ? values['color']! as int : null,
      collapsed: values['collapsed'] == true,
      parentId: values['parent'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasFrame &&
      other.id == id &&
      other.position == position &&
      other.size == size &&
      other.title == title &&
      other.description == description &&
      other.color == color &&
      other.collapsed == collapsed &&
      other.parentId == parentId;

  @override
  int get hashCode => Object.hash(
        id,
        position,
        size,
        title,
        description,
        color,
        collapsed,
        parentId,
      );
}

/// One freehand mark. Drawing is kept apart from cards on purpose — a stroke is
/// not something you can connect, group or turn into a page.
@immutable
class CanvasStroke {
  const CanvasStroke({
    required this.id,
    required this.points,
    this.tool = CanvasStrokeTool.pen,
    this.color,
    this.width = 3,
  });

  factory CanvasStroke.create({
    required List<Offset> points,
    String? id,
    CanvasStrokeTool tool = CanvasStrokeTool.pen,
    int? color,
    double width = 3,
  }) =>
      CanvasStroke(
        id: id ?? newCanvasId('s'),
        points: List<Offset>.unmodifiable(points),
        tool: tool,
        color: color,
        width: width,
      );

  final String id;
  final List<Offset> points;
  final CanvasStrokeTool tool;
  final int? color;
  final double width;

  Rect get bounds {
    if (points.isEmpty) {
      return Rect.zero;
    }
    var left = points.first.dx;
    var top = points.first.dy;
    var right = left;
    var bottom = top;
    for (final point in points) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(width);
  }

  CanvasStroke movedBy(Offset delta) => CanvasStroke(
        id: id,
        points: [for (final point in points) point + delta],
        tool: tool,
        color: color,
        width: width,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        // Flattened, because a list of pairs doubles the stored size for no
        // gain and this is the one thing a canvas can have thousands of.
        'points': [
          for (final point in points) ...[point.dx, point.dy],
        ],
        if (tool != CanvasStrokeTool.pen) 'tool': tool.id,
        if (color != null) 'color': color,
        if (width != 3) 'width': width,
      };

  static CanvasStroke? fromJson(Map<String, Object?> values) {
    final id = values['id'];
    final raw = values['points'];
    if (id is! String || id.isEmpty || raw is! List || raw.length < 4) {
      return null;
    }
    final points = <Offset>[];
    for (var index = 0; index + 1 < raw.length; index += 2) {
      final x = _readDouble(raw[index]);
      final y = _readDouble(raw[index + 1]);
      if (x == null || y == null) {
        continue;
      }
      points.add(Offset(x, y));
    }
    if (points.length < 2) {
      return null;
    }
    return CanvasStroke(
      id: id,
      points: List<Offset>.unmodifiable(points),
      tool: CanvasStrokeTool.fromId(values['tool'] as String?),
      color: values['color'] is int ? values['color']! as int : null,
      width: _readDouble(values['width']) ?? 3,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasStroke &&
      other.id == id &&
      other.tool == tool &&
      other.color == color &&
      other.width == width &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(id, tool, color, width, points.length);
}

/// Where the canvas was left, so reopening it does not start at the origin.
@immutable
class CanvasViewport {
  const CanvasViewport({
    this.offset = Offset.zero,
    this.zoom = 1,
  });

  final Offset offset;
  final double zoom;

  Map<String, Object?> toJson() => {
        'x': offset.dx,
        'y': offset.dy,
        'zoom': zoom,
      };

  static CanvasViewport fromJson(Map<String, Object?> values) => CanvasViewport(
        offset: Offset(
          _readDouble(values['x']) ?? 0,
          _readDouble(values['y']) ?? 0,
        ),
        zoom: (_readDouble(values['zoom']) ?? 1).clamp(0.05, 8),
      );

  @override
  bool operator ==(Object other) =>
      other is CanvasViewport && other.offset == offset && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(offset, zoom);
}

/// How a canvas looks and behaves, as distinct from what is on it.
@immutable
class CanvasSettings {
  const CanvasSettings({
    this.background = CanvasBackground.dots,
    this.theme = CanvasTheme.auto,
    this.gridSize = 24,
    this.snapToGrid = false,
    this.snapToObjects = true,
    this.showMinimap = false,
    this.showOutline = false,
    this.viewport = const CanvasViewport(),
  });

  final CanvasBackground background;
  final CanvasTheme theme;
  final double gridSize;
  final bool snapToGrid;
  final bool snapToObjects;
  final bool showMinimap;
  final bool showOutline;
  final CanvasViewport viewport;

  CanvasSettings copyWith({
    CanvasBackground? background,
    CanvasTheme? theme,
    double? gridSize,
    bool? snapToGrid,
    bool? snapToObjects,
    bool? showMinimap,
    bool? showOutline,
    CanvasViewport? viewport,
  }) =>
      CanvasSettings(
        background: background ?? this.background,
        theme: theme ?? this.theme,
        gridSize: gridSize ?? this.gridSize,
        snapToGrid: snapToGrid ?? this.snapToGrid,
        snapToObjects: snapToObjects ?? this.snapToObjects,
        showMinimap: showMinimap ?? this.showMinimap,
        showOutline: showOutline ?? this.showOutline,
        viewport: viewport ?? this.viewport,
      );

  Map<String, Object?> toJson() => {
        'background': background.id,
        if (theme != CanvasTheme.auto) 'theme': theme.id,
        if (gridSize != 24) 'gridSize': gridSize,
        if (snapToGrid) 'snapToGrid': true,
        if (!snapToObjects) 'snapToObjects': false,
        if (showMinimap) 'minimap': true,
        if (showOutline) 'outline': true,
        'viewport': viewport.toJson(),
      };

  static CanvasSettings fromJson(Map<String, Object?> values) => CanvasSettings(
        background: CanvasBackground.fromId(values['background'] as String?),
        theme: CanvasTheme.fromId(values['theme'] as String?),
        gridSize: (_readDouble(values['gridSize']) ?? 24).clamp(8, 160),
        snapToGrid: values['snapToGrid'] == true,
        snapToObjects: values['snapToObjects'] != false,
        showMinimap: values['minimap'] == true,
        showOutline: values['outline'] == true,
        viewport: values['viewport'] is Map
            ? CanvasViewport.fromJson(
                Map<String, Object?>.from(values['viewport']! as Map),
              )
            : const CanvasViewport(),
      );

  @override
  bool operator ==(Object other) =>
      other is CanvasSettings &&
      other.background == background &&
      other.theme == theme &&
      other.gridSize == gridSize &&
      other.snapToGrid == snapToGrid &&
      other.snapToObjects == snapToObjects &&
      other.showMinimap == showMinimap &&
      other.showOutline == showOutline &&
      other.viewport == viewport;

  @override
  int get hashCode => Object.hash(
        background,
        theme,
        gridSize,
        snapToGrid,
        snapToObjects,
        showMinimap,
        showOutline,
        viewport,
      );
}

/// Everything on one canvas.
@immutable
class CanvasDocument {
  const CanvasDocument({
    this.nodes = const <CanvasNode>[],
    this.edges = const <CanvasEdge>[],
    this.frames = const <CanvasFrame>[],
    this.strokes = const <CanvasStroke>[],
    this.settings = const CanvasSettings(),
  });

  factory CanvasDocument.blank() => const CanvasDocument();

  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final List<CanvasFrame> frames;
  final List<CanvasStroke> strokes;
  final CanvasSettings settings;

  bool get isEmpty =>
      nodes.isEmpty && edges.isEmpty && frames.isEmpty && strokes.isEmpty;

  int get objectCount => nodes.length + frames.length;

  CanvasNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  CanvasFrame? frameById(String id) {
    for (final frame in frames) {
      if (frame.id == id) {
        return frame;
      }
    }
    return null;
  }

  CanvasEdge? edgeById(String id) {
    for (final edge in edges) {
      if (edge.id == id) {
        return edge;
      }
    }
    return null;
  }

  /// Every card filed under a frame, including those in frames inside it.
  List<CanvasNode> nodesInFrame(String frameId) {
    final wanted = <String>{frameId, ...descendantFrames(frameId)};
    return [
      for (final node in nodes)
        if (node.frameId != null && wanted.contains(node.frameId)) node,
    ];
  }

  Set<String> descendantFrames(String frameId) {
    final found = <String>{};
    var frontier = <String>{frameId};
    while (frontier.isNotEmpty) {
      final next = <String>{};
      for (final frame in frames) {
        final parent = frame.parentId;
        if (parent != null &&
            frontier.contains(parent) &&
            found.add(frame.id)) {
          next.add(frame.id);
        }
      }
      frontier = next;
    }
    return found;
  }

  /// The box every object on the canvas fits inside.
  Rect get bounds {
    final boxes = <Rect>[
      for (final frame in frames) frame.rect,
      for (final node in nodes) node.rect,
      for (final stroke in strokes) stroke.bounds,
    ];
    return unionOfCanvasRects(boxes);
  }

  Rect boundsOf(Iterable<String> ids) {
    final wanted = ids.toSet();
    final boxes = <Rect>[
      for (final frame in frames)
        if (wanted.contains(frame.id)) frame.rect,
      for (final node in nodes)
        if (wanted.contains(node.id)) node.rect,
    ];
    return unionOfCanvasRects(boxes);
  }

  CanvasDocument copyWith({
    List<CanvasNode>? nodes,
    List<CanvasEdge>? edges,
    List<CanvasFrame>? frames,
    List<CanvasStroke>? strokes,
    CanvasSettings? settings,
  }) =>
      CanvasDocument(
        nodes: nodes ?? this.nodes,
        edges: edges ?? this.edges,
        frames: frames ?? this.frames,
        strokes: strokes ?? this.strokes,
        settings: settings ?? this.settings,
      );

  CanvasDocument withNode(CanvasNode node) {
    final index = nodes.indexWhere((existing) => existing.id == node.id);
    final next = [...nodes];
    if (index < 0) {
      next.add(node);
    } else {
      next[index] = node;
    }
    return copyWith(nodes: next);
  }

  CanvasDocument withNodes(Iterable<CanvasNode> updated) {
    final byId = {for (final node in updated) node.id: node};
    if (byId.isEmpty) {
      return this;
    }
    final next = [
      for (final node in nodes) byId.remove(node.id) ?? node,
      ...byId.values,
    ];
    return copyWith(nodes: next);
  }

  CanvasDocument withFrame(CanvasFrame frame) {
    final index = frames.indexWhere((existing) => existing.id == frame.id);
    final next = [...frames];
    if (index < 0) {
      next.add(frame);
    } else {
      next[index] = frame;
    }
    return copyWith(frames: next);
  }

  CanvasDocument withEdge(CanvasEdge edge) {
    final index = edges.indexWhere((existing) => existing.id == edge.id);
    final next = [...edges];
    if (index < 0) {
      next.add(edge);
    } else {
      next[index] = edge;
    }
    return copyWith(edges: next);
  }

  /// Removing objects also removes anything that only made sense with them —
  /// a connection to a card that is gone is not a connection.
  CanvasDocument without(Iterable<String> ids) {
    final wanted = ids.toSet();
    if (wanted.isEmpty) {
      return this;
    }
    final droppedFrames = <String>{
      for (final frame in frames)
        if (wanted.contains(frame.id)) ...[
          frame.id,
          ...descendantFrames(frame.id),
        ],
    };
    final keptNodes = [
      for (final node in nodes)
        if (!wanted.contains(node.id))
          droppedFrames.contains(node.frameId)
              ? node.copyWith(frameId: null)
              : node,
    ];
    final keptIds = {for (final node in keptNodes) node.id};
    return CanvasDocument(
      nodes: keptNodes,
      edges: [
        for (final edge in edges)
          if (!wanted.contains(edge.id) &&
              keptIds.contains(edge.from) &&
              keptIds.contains(edge.to))
            edge,
      ],
      frames: [
        for (final frame in frames)
          if (!droppedFrames.contains(frame.id))
            droppedFrames.contains(frame.parentId)
                ? frame.copyWith(parentId: null)
                : frame,
      ],
      strokes: [
        for (final stroke in strokes)
          if (!wanted.contains(stroke.id)) stroke,
      ],
      settings: settings,
    );
  }

  Map<String, Object?> toJson() => {
        if (nodes.isNotEmpty)
          'nodes': [for (final node in nodes) node.toJson()],
        if (edges.isNotEmpty)
          'edges': [for (final edge in edges) edge.toJson()],
        if (frames.isNotEmpty)
          'frames': [for (final frame in frames) frame.toJson()],
        if (strokes.isNotEmpty)
          'strokes': [for (final stroke in strokes) stroke.toJson()],
        'settings': settings.toJson(),
      };

  static CanvasDocument fromJson(Map<String, Object?> values) {
    List<T> read<T>(String key, T? Function(Map<String, Object?>) parse) {
      final raw = values[key];
      if (raw is! List) {
        return <T>[];
      }
      final parsed = <T>[];
      for (final entry in raw) {
        if (entry is! Map) {
          continue;
        }
        final value = parse(Map<String, Object?>.from(entry));
        if (value != null) {
          parsed.add(value);
        }
      }
      return parsed;
    }

    final nodes = read<CanvasNode>('nodes', CanvasNode.fromJson);
    final ids = {for (final node in nodes) node.id};
    return CanvasDocument(
      nodes: nodes,
      // A connection whose ends are gone is dropped rather than drawn into
      // nowhere; that is also what makes a hand-edited document safe to open.
      edges: [
        for (final edge in read<CanvasEdge>('edges', CanvasEdge.fromJson))
          if (ids.contains(edge.from) && ids.contains(edge.to)) edge,
      ],
      frames: read<CanvasFrame>('frames', CanvasFrame.fromJson),
      strokes: read<CanvasStroke>('strokes', CanvasStroke.fromJson),
      settings: values['settings'] is Map
          ? CanvasSettings.fromJson(
              Map<String, Object?>.from(values['settings']! as Map),
            )
          : const CanvasSettings(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasDocument &&
      other.settings == settings &&
      listEquals(other.nodes, nodes) &&
      listEquals(other.edges, edges) &&
      listEquals(other.frames, frames) &&
      listEquals(other.strokes, strokes);

  @override
  int get hashCode => Object.hash(
        settings,
        nodes.length,
        edges.length,
        frames.length,
        strokes.length,
        Object.hashAll(nodes),
        Object.hashAll(edges),
        Object.hashAll(frames),
      );
}

const Object _unset = Object();

/// The smallest box holding every one of [rects]; [Rect.zero] for none.
Rect unionOfCanvasRects(Iterable<Rect> rects) {
  var seen = false;
  var left = 0.0;
  var top = 0.0;
  var right = 0.0;
  var bottom = 0.0;
  for (final rect in rects) {
    if (!seen) {
      seen = true;
      left = rect.left;
      top = rect.top;
      right = rect.right;
      bottom = rect.bottom;
      continue;
    }
    left = math.min(left, rect.left);
    top = math.min(top, rect.top);
    right = math.max(right, rect.right);
    bottom = math.max(bottom, rect.bottom);
  }
  return seen ? Rect.fromLTRB(left, top, right, bottom) : Rect.zero;
}

double? _readDouble(Object? value) {
  if (value is num) {
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
