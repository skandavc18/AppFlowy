import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

/// The element kinds this editor draws.
///
/// Anything else in a scene — frames, embeds, iframes — is carried through
/// untouched so a file written by Excalidraw survives a round trip, it is
/// simply not drawn.
abstract final class DrawElementType {
  static const rectangle = 'rectangle';
  static const diamond = 'diamond';
  static const ellipse = 'ellipse';
  static const line = 'line';
  static const arrow = 'arrow';
  static const freedraw = 'freedraw';
  static const text = 'text';
  static const image = 'image';

  static const drawable = <String>{
    rectangle,
    diamond,
    ellipse,
    line,
    arrow,
    freedraw,
    text,
    image,
  };

  static bool isLinear(String type) =>
      type == line || type == arrow || type == freedraw;
}

/// One element of a drawing.
///
/// It is a thin, typed view over the raw map so every field Excalidraw writes
/// — bindings, group ids, fractional indices, custom data — is preserved even
/// though this editor does not use it. Losing them would make a drawing
/// round-tripped through AppFlowy worse than it arrived.
@immutable
class DrawElement {
  const DrawElement(this.data);

  factory DrawElement.create({
    required String type,
    required double x,
    required double y,
    double width = 0,
    double height = 0,
    String strokeColor = '#1e1e1e',
    String backgroundColor = 'transparent',
    String fillStyle = 'solid',
    double strokeWidth = 2,
    String strokeStyle = 'solid',
    double roughness = 1,
    double opacity = 100,
    List<Offset> points = const <Offset>[],
    String? text,
    double fontSize = 20,
    int fontFamily = 1,
    String textAlign = 'left',
    bool roundEdges = true,
  }) {
    final random = math.Random();
    return DrawElement(<String, dynamic>{
      'id': newDrawElementId(),
      'type': type,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'angle': 0,
      'strokeColor': strokeColor,
      'backgroundColor': backgroundColor,
      'fillStyle': fillStyle,
      'strokeWidth': strokeWidth,
      'strokeStyle': strokeStyle,
      'roughness': roughness,
      'opacity': opacity,
      'groupIds': <String>[],
      'frameId': null,
      'roundness': roundEdges && !DrawElementType.isLinear(type)
          ? <String, dynamic>{'type': 3}
          : null,
      'seed': random.nextInt(0x7FFFFFFF),
      'version': 1,
      'versionNonce': random.nextInt(0x7FFFFFFF),
      'isDeleted': false,
      'boundElements': null,
      'updated': DateTime.now().millisecondsSinceEpoch,
      'link': null,
      'locked': false,
      if (points.isNotEmpty)
        'points': [
          for (final point in points) [point.dx, point.dy],
        ],
      if (text != null) ...<String, dynamic>{
        'text': text,
        'originalText': text,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'textAlign': textAlign,
        'verticalAlign': 'top',
        'containerId': null,
        'lineHeight': 1.25,
        'autoResize': true,
      },
    });
  }

  final Map<String, dynamic> data;

  String get id => data['id'] as String? ?? '';
  String get type => data['type'] as String? ?? '';
  double get x => _number(data['x']);
  double get y => _number(data['y']);
  double get width => _number(data['width']);
  double get height => _number(data['height']);
  double get angle => _number(data['angle']);
  String get strokeColor => data['strokeColor'] as String? ?? '#1e1e1e';
  String get backgroundColor =>
      data['backgroundColor'] as String? ?? 'transparent';
  String get fillStyle => data['fillStyle'] as String? ?? 'solid';
  double get strokeWidth => _number(data['strokeWidth'], 2);
  String get strokeStyle => data['strokeStyle'] as String? ?? 'solid';
  double get roughness => _number(data['roughness'], 1);
  double get opacity => _number(data['opacity'], 100);
  int get seed => (data['seed'] as num?)?.toInt() ?? 1;
  bool get isDeleted => data['isDeleted'] as bool? ?? false;
  bool get locked => data['locked'] as bool? ?? false;
  bool get roundEdges => data['roundness'] != null;
  String get text => data['text'] as String? ?? '';
  double get fontSize => _number(data['fontSize'], 20);
  String get textAlign => data['textAlign'] as String? ?? 'left';
  String get verticalAlign => data['verticalAlign'] as String? ?? 'top';

  /// Excalidraw's own line height, as a multiple of the font size.
  double get lineHeight => _number(data['lineHeight'], 1.25);

  /// The shape this text is bound to, if it is a label rather than free text.
  String? get containerId => data['containerId'] as String?;

  /// The corner style: 1 legacy, 2 proportional, 3 adaptive.
  int? get roundnessType =>
      (data['roundness'] is Map ? (data['roundness'] as Map)['type'] : null)
              is num
          ? ((data['roundness'] as Map)['type'] as num).toInt()
          : null;

  String? get fileId => data['fileId'] as String?;

  /// Stroke points relative to [x], [y].
  List<Offset> get points {
    final raw = data['points'];
    if (raw is! List) {
      return const <Offset>[];
    }
    return [
      for (final entry in raw)
        if (entry is List && entry.length >= 2)
          Offset(_number(entry[0]), _number(entry[1])),
    ];
  }

  Rect get bounds {
    if (DrawElementType.isLinear(type)) {
      final list = points;
      if (list.isEmpty) {
        return Rect.fromLTWH(x, y, width, height);
      }
      var minX = list.first.dx;
      var maxX = list.first.dx;
      var minY = list.first.dy;
      var maxY = list.first.dy;
      for (final point in list) {
        minX = math.min(minX, point.dx);
        maxX = math.max(maxX, point.dx);
        minY = math.min(minY, point.dy);
        maxY = math.max(maxY, point.dy);
      }
      return Rect.fromLTRB(x + minX, y + minY, x + maxX, y + maxY);
    }
    final rect = Rect.fromLTWH(x, y, width, height);
    // A dragged shape can end up with a negative extent; normalise so hit
    // testing and handles never see an inverted box.
    return Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );
  }

  DrawElement change(Map<String, dynamic> changes) {
    final next = <String, dynamic>{...data, ...changes};
    next['version'] = (data['version'] as num? ?? 0).toInt() + 1;
    next['versionNonce'] = math.Random().nextInt(0x7FFFFFFF);
    next['updated'] = DateTime.now().millisecondsSinceEpoch;
    return DrawElement(next);
  }

  DrawElement movedBy(Offset delta) =>
      change({'x': x + delta.dx, 'y': y + delta.dy});

  DrawElement withPoints(List<Offset> value) {
    var minX = 0.0;
    var minY = 0.0;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final point in value) {
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
    }
    return change({
      'points': [
        for (final point in value) [point.dx, point.dy],
      ],
      'width': maxX - minX,
      'height': maxY - minY,
    });
  }

  /// Scales the element into [target], keeping strokes proportional.
  DrawElement resizedTo(Rect target) {
    if (DrawElementType.isLinear(type)) {
      final current = bounds;
      final scaleX = current.width == 0 ? 1.0 : target.width / current.width;
      final scaleY = current.height == 0 ? 1.0 : target.height / current.height;
      return change({
        'x': target.left,
        'y': target.top,
        'points': [
          for (final point in points) [point.dx * scaleX, point.dy * scaleY],
        ],
        'width': target.width,
        'height': target.height,
      });
    }
    if (type == DrawElementType.text) {
      final current = bounds;
      final scale = current.height == 0 ? 1.0 : target.height / current.height;
      return change({
        'x': target.left,
        'y': target.top,
        'width': target.width,
        'height': target.height,
        'fontSize': math.max(8, fontSize * scale),
      });
    }
    return change({
      'x': target.left,
      'y': target.top,
      'width': target.width,
      'height': target.height,
    });
  }

  Map<String, dynamic> toJson() => data;
}

double _number(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;

/// The parts of the Excalidraw app state worth keeping.
///
/// Everything else in the file's `appState` is carried through untouched.
@immutable
class DrawAppState {
  const DrawAppState(this.data);

  factory DrawAppState.initial() => const DrawAppState(<String, dynamic>{
        'gridSize': null,
        'viewBackgroundColor': '#ffffff',
      });

  final Map<String, dynamic> data;

  String get viewBackgroundColor =>
      data['viewBackgroundColor'] as String? ?? '#ffffff';

  double? get gridSize {
    final value = data['gridSize'];
    return value is num ? value.toDouble() : null;
  }

  DrawAppState change(Map<String, dynamic> changes) =>
      DrawAppState(<String, dynamic>{...data, ...changes});

  Map<String, dynamic> toJson() => data;
}

/// A whole drawing: elements, app state and any embedded files.
///
/// This is the `.excalidraw` shape exactly — `type`, `version`, `source`,
/// `elements`, `appState`, `files` — so a scene can be handed to Excalidraw
/// or read back from it without a converter in between.
@immutable
class DrawScene {
  const DrawScene({
    required this.elements,
    required this.appState,
    this.files = const <String, dynamic>{},
    this.version = 2,
    this.source = 'https://appflowy.io',
  });

  factory DrawScene.empty() => DrawScene(
        elements: const <DrawElement>[],
        appState: DrawAppState.initial(),
      );

  factory DrawScene.fromJson(Map<String, dynamic> json) => DrawScene(
        version: (json['version'] as num?)?.toInt() ?? 2,
        source: json['source'] as String? ?? 'https://appflowy.io',
        elements: [
          for (final entry in (json['elements'] as List<dynamic>? ?? const []))
            if (entry is Map) DrawElement(Map<String, dynamic>.from(entry)),
        ],
        appState: json['appState'] is Map
            ? DrawAppState(Map<String, dynamic>.from(json['appState'] as Map))
            : DrawAppState.initial(),
        files: json['files'] is Map
            ? Map<String, dynamic>.from(json['files'] as Map)
            : const <String, dynamic>{},
      );

  /// Reads a `.excalidraw` document, or an empty scene when it cannot be
  /// understood.
  static DrawScene? decode(String source) {
    if (source.trim().isEmpty) {
      return DrawScene.empty();
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return DrawScene.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  final List<DrawElement> elements;
  final DrawAppState appState;
  final Map<String, dynamic> files;
  final int version;
  final String source;

  /// The elements that are actually drawn, in paint order.
  List<DrawElement> get visible => [
        for (final element in elements)
          if (!element.isDeleted &&
              DrawElementType.drawable.contains(element.type))
            element,
      ];

  bool get isEmpty => visible.isEmpty;

  Rect? get contentBounds {
    Rect? bounds;
    for (final element in visible) {
      final rect = element.bounds;
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    return bounds;
  }

  DrawScene copyWith({
    List<DrawElement>? elements,
    DrawAppState? appState,
    Map<String, dynamic>? files,
  }) =>
      DrawScene(
        elements: elements ?? this.elements,
        appState: appState ?? this.appState,
        files: files ?? this.files,
        version: version,
        source: source,
      );

  DrawElement? find(String id) {
    for (final element in elements) {
      if (element.id == id) {
        return element;
      }
    }
    return null;
  }

  DrawScene replace(DrawElement element) => copyWith(
        elements: [
          for (final existing in elements)
            if (existing.id == element.id) element else existing,
        ],
      );

  DrawScene replaceAll(Iterable<DrawElement> updated) {
    final byId = {for (final element in updated) element.id: element};
    return copyWith(
      elements: [
        for (final existing in elements) byId[existing.id] ?? existing,
      ],
    );
  }

  DrawScene add(DrawElement element) =>
      copyWith(elements: [...elements, element]);

  DrawScene removeAll(Set<String> ids) => copyWith(
        elements: [
          for (final element in elements)
            if (!ids.contains(element.id)) element,
        ],
      );

  /// Brings [ids] to the front, which is the whole of the layer model this
  /// editor needs — Excalidraw itself orders purely by array position.
  DrawScene bringToFront(Set<String> ids) {
    final moving = <DrawElement>[];
    final rest = <DrawElement>[];
    for (final element in elements) {
      (ids.contains(element.id) ? moving : rest).add(element);
    }
    return copyWith(elements: [...rest, ...moving]);
  }

  DrawScene sendToBack(Set<String> ids) {
    final moving = <DrawElement>[];
    final rest = <DrawElement>[];
    for (final element in elements) {
      (ids.contains(element.id) ? moving : rest).add(element);
    }
    return copyWith(elements: [...moving, ...rest]);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'excalidraw',
        'version': version,
        'source': source,
        'elements': [for (final element in elements) element.toJson()],
        'appState': appState.toJson(),
        'files': files,
      };

  String encode({bool pretty = false}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());
}

int _idCounter = 0;

String newDrawElementId() {
  _idCounter += 1;
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = math.Random().nextInt(0x3FFFFFFF).toRadixString(36);
  return '$stamp$salt$_idCounter';
}
