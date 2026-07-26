import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How long a full page turn takes when it is not driven by a finger.
const pageTurnDuration = Duration(milliseconds: 430);

/// How far the leading corner runs ahead of the trailing one, as a fraction of
/// the leaf width. Without it the fold is a straight vertical line and the page
/// reads as a rolling shutter instead of paper.
const _curlSkew = 0.17;

/// Radius of the roll at the height of the turn, relative to the shorter side.
const _curlRadius = 0.155;

/// A very small amount of foreshortening. Paper lifting off the surface comes
/// closer to the reader, so it grows a little.
const _curlPerspective = 0.00042;

/// The grid the leaf is deformed on. Fine enough that the roll reads as a
/// smooth cylinder, coarse enough to stay far inside a frame budget.
const _curlColumns = 34;
const _curlRows = 18;

/// A page that stays put for the whole turn.
@immutable
class PageTurnStaticPage {
  const PageTurnStaticPage({
    required this.image,
    required this.rect,
    required this.outerOnRight,
  });

  final ui.Image image;
  final Rect rect;

  /// Which side carries the cut edge of the paper stack.
  final bool outerOnRight;
}

/// Everything needed to paint one page turn.
///
/// The scene is built once, from images that are already rasterised, so no PDF
/// page is ever decoded while the animation runs.
@immutable
class PageTurnScene {
  const PageTurnScene({
    required this.background,
    required this.paper,
    required this.paperEdge,
    required this.underlays,
    required this.leafFront,
    required this.leafBack,
    required this.leafRect,
    required this.pivotOnLeft,
    required this.leadFromBottom,
    required this.fadeLeafAtEnd,
    this.spineCenter,
  });

  final Color background;
  final Color paper;
  final Color paperEdge;

  /// Painted flat, in order, before the leaf.
  final List<PageTurnStaticPage> underlays;

  final ui.Image leafFront;

  /// The reverse of the sheet. Null means the leaf is a lone page, so its back
  /// is shown as washed-out paper with the front ghosting through.
  final ui.Image? leafBack;

  final Rect leafRect;

  /// True while the leaf rolls towards the left, which is a forward turn.
  final bool pivotOnLeft;

  final bool leadFromBottom;

  /// Single page reading has nothing for the leaf to land on, so it dissolves
  /// as it leaves. In a spread it settles exactly onto the facing page.
  final bool fadeLeafAtEnd;

  /// X of the book spine, when there is one, for the ambient gutter shadow.
  final double? spineCenter;
}

/// The deformed grid of a turning leaf.
///
/// The sheet is modelled as a cylinder tangent to the flat page at the fold:
/// everything before the fold is still lying down, everything past it wraps
/// around the roll and then falls back on the far side. The fold is slanted so
/// the leading corner lifts first and the rest of the page follows it.
@immutable
class PageCurlSurface {
  const PageCurlSurface({
    required this.positions,
    required this.textureCoordinates,
    required this.colors,
    required this.frontIndices,
    required this.backIndices,
    required this.leadingEdge,
    required this.foldLine,
    required this.lift,
    required this.shadowWidth,
  });

  /// Canvas space, two floats per vertex.
  final Float32List positions;

  /// Normalised 0..1, two floats per vertex; scaled per texture when painting.
  final Float32List textureCoordinates;

  final Int32List colors;

  /// Triangles still showing the front of the sheet, in painter order.
  final Uint16List frontIndices;

  /// Triangles that have rolled far enough to show the reverse.
  final Uint16List backIndices;

  /// The outer edge of the leaf, used to give the paper thickness.
  final List<Offset> leadingEdge;

  /// Where the paper leaves the flat surface; the cast shadow follows it.
  final List<Offset> foldLine;

  /// 0 when the page lies flat, 1 at the height of the turn.
  final double lift;

  final double shadowWidth;
}

/// Deforms a flat page rectangle into a rolling sheet of paper.
///
/// [progress] runs 0..1. [pivotOnLeft] rolls the leaf towards the left (a
/// forward turn); the geometry is mirrored for a backward turn.
PageCurlSurface buildPageCurlSurface({
  required Rect rect,
  required double progress,
  required bool pivotOnLeft,
  required bool leadFromBottom,
  double opacity = 1,
  int columns = _curlColumns,
  int rows = _curlRows,
}) {
  final p = progress.clamp(0.0, 1.0);
  final width = math.max(rect.width, 1.0);
  final height = math.max(rect.height, 1.0);

  // The roll opens up and closes again over the turn, so the sheet starts and
  // ends perfectly flat.
  final shape = math.sin(math.pi * p);
  final radius = math.min(width, height) * _curlRadius * shape;
  final skew = width * _curlSkew * math.pow(shape, 0.6).toDouble();

  // The geometry is driven by where the outer edge has to be rather than by
  // the fold, so the leaf lands exactly mirrored on the facing page instead of
  // drifting past it.
  final edgeAtLeadingCorner = width * (1 - 2 * p);
  final arcLength = math.pi * radius;

  final centerY = height / 2;
  final contact = math.max(radius * 1.1, 14.0);
  final alpha = (opacity.clamp(0.0, 1.0) * 255).round();

  final vertexCount = (columns + 1) * (rows + 1);
  final positions = Float32List(vertexCount * 2);
  final texture = Float32List(vertexCount * 2);
  final colors = Int32List(vertexCount);
  final angles = Float32List(vertexCount);
  final leadingEdge = <Offset>[];
  final foldLine = <Offset>[];

  for (var j = 0; j <= rows; j++) {
    final t = j / rows;
    final v = t * height;
    final lead = leadFromBottom ? t : 1 - t;
    // The trailing corner lags a whole skew behind the leading one.
    final edge = edgeAtLeadingCorner + skew * (1 - lead);
    final fold = math.min((edge + width - arcLength) / 2, width);

    for (var i = 0; i <= columns; i++) {
      final s = i / columns;
      final u = s * width;

      double x;
      double z;
      double angle;
      if (u <= fold || radius <= 0) {
        x = u;
        z = 0;
        angle = 0;
      } else {
        final arc = u - fold;
        angle = arc / radius;
        if (angle <= math.pi) {
          x = fold + radius * math.sin(angle);
          z = radius * (1 - math.cos(angle));
        } else {
          // Past the half roll the paper lies back down on the far side.
          x = fold - (arc - arcLength);
          z = 2 * radius;
          angle = math.pi;
        }
      }

      final scale = 1 + z * _curlPerspective;
      final localX = pivotOnLeft ? x * scale : width - x * scale;
      final localY = centerY + (v - centerY) * scale;

      final index = j * (columns + 1) + i;
      positions[index * 2] = rect.left + localX;
      positions[index * 2 + 1] = rect.top + localY;
      texture[index * 2] = s;
      texture[index * 2 + 1] = t;
      angles[index] = angle;

      double shade;
      if (angle <= math.pi / 2) {
        // The front turns away from the light as it rises.
        shade = 0.70 + 0.30 * math.cos(angle);
      } else {
        // The reverse comes back into it.
        shade = 0.84 + 0.14 * -math.cos(angle);
      }
      if (u < fold && fold - u < contact) {
        // Paper sitting in the shadow of its own roll.
        shade *= 1 - 0.17 * (1 - (fold - u) / contact);
      }
      final level = (shade.clamp(0.0, 1.0) * 255).round();
      colors[index] = (alpha << 24) | (level << 16) | (level << 8) | level;

      if (i == columns) {
        leadingEdge.add(
          Offset(positions[index * 2], positions[index * 2 + 1]),
        );
      }
    }

    final clampedFold = fold.clamp(-width * 0.25, width).toDouble();
    final foldX = pivotOnLeft ? clampedFold : width - clampedFold;
    foldLine.add(Offset(rect.left + foldX, rect.top + v));
  }

  // Front triangles first: they always sit lower than the rolled part, so
  // painter order alone resolves the overlap.
  final front = <int>[];
  final back = <int>[];
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < columns; i++) {
      final a = j * (columns + 1) + i;
      final b = a + 1;
      final c = a + columns + 1;
      final d = c + 1;
      final mean = (angles[a] + angles[b] + angles[c] + angles[d]) / 4;
      final target = mean > math.pi / 2 ? back : front;
      target
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(b)
        ..add(d)
        ..add(c);
    }
  }

  return PageCurlSurface(
    positions: positions,
    textureCoordinates: texture,
    colors: colors,
    frontIndices: Uint16List.fromList(front),
    backIndices: Uint16List.fromList(back),
    leadingEdge: leadingEdge,
    foldLine: foldLine,
    lift: shape,
    shadowWidth: math.min(radius * 2.4, width * 0.34),
  );
}

/// Paints a whole page turn: the pages that stay put, the shadow the leaf
/// casts on them, and the leaf itself.
class PageTurnPainter extends CustomPainter {
  const PageTurnPainter({required this.scene, required this.progress});

  final PageTurnScene scene;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = scene.background,
    );

    final surface = buildPageCurlSurface(
      rect: scene.leafRect,
      progress: progress,
      pivotOnLeft: scene.pivotOnLeft,
      leadFromBottom: scene.leadFromBottom,
      opacity: _leafOpacity,
    );

    for (final page in scene.underlays) {
      _paintPaperStack(canvas, page, surface.lift);
      _paintFlatPage(canvas, page);
    }
    _paintSpineShade(canvas, size);
    _paintCastShadow(canvas, surface);
    _paintLeaf(canvas, surface);
    _paintLeafEdge(canvas, surface);
  }

  double get _leafOpacity {
    if (!scene.fadeLeafAtEnd) {
      return 1;
    }
    const start = 0.86;
    return progress <= start ? 1 : 1 - (progress - start) / (1 - start);
  }

  void _paintFlatPage(Canvas canvas, PageTurnStaticPage page) {
    canvas.drawImageRect(
      page.image,
      Rect.fromLTWH(
        0,
        0,
        page.image.width.toDouble(),
        page.image.height.toDouble(),
      ),
      page.rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  /// A few hairlines along the cut edge so the paper is not infinitely thin.
  /// The stack breathes a little as the leaf moves across it.
  void _paintPaperStack(
    Canvas canvas,
    PageTurnStaticPage page,
    double lift,
  ) {
    final spread = 1.1 * (1 + lift * 0.35);
    final direction = page.outerOnRight ? 1.0 : -1.0;
    for (var layer = 3; layer >= 1; layer--) {
      final dx = direction * layer * spread;
      final inset = layer * 1.4;
      final paint = Paint()
        ..color = scene.paperEdge.withValues(alpha: 0.30 - layer * 0.06)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      final edgeX = page.outerOnRight ? page.rect.right : page.rect.left;
      canvas.drawLine(
        Offset(edgeX + dx, page.rect.top + inset),
        Offset(edgeX + dx, page.rect.bottom - inset),
        paint,
      );
    }
  }

  void _paintSpineShade(Canvas canvas, Size size) {
    final spine = scene.spineCenter;
    if (spine == null) {
      return;
    }
    final band = math.max(size.width * 0.03, 22.0);
    final rect = Rect.fromLTRB(spine - band, 0, spine + band, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.11),
            Colors.black.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  /// The soft shadow the raised paper drops on whatever it uncovers.
  void _paintCastShadow(Canvas canvas, PageCurlSurface surface) {
    if (surface.lift <= 0.02 || surface.foldLine.length < 2) {
      return;
    }
    final direction = scene.pivotOnLeft ? -1.0 : 1.0;
    final offset = Offset(direction * surface.shadowWidth, 0);
    final path = Path()
      ..addPolygon(
        [
          ...surface.foldLine,
          ...surface.foldLine.reversed.map((point) => point + offset),
        ],
        true,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20 * surface.lift)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );
  }

  void _paintLeaf(Canvas canvas, PageCurlSurface surface) {
    final back = scene.leafBack;
    if (surface.frontIndices.isNotEmpty) {
      _drawMesh(
        canvas,
        surface,
        scene.leafFront,
        surface.frontIndices,
        colorFilter: null,
      );
    }
    if (surface.backIndices.isNotEmpty) {
      _drawMesh(
        canvas,
        surface,
        back ?? scene.leafFront,
        surface.backIndices,
        // A lone sheet has nothing printed on its reverse, so the front only
        // ghosts through the paper.
        colorFilter: back == null ? _washTowards(scene.paper, 0.16) : null,
      );
    }
  }

  void _drawMesh(
    Canvas canvas,
    PageCurlSurface surface,
    ui.Image image,
    Uint16List indices, {
    required ColorFilter? colorFilter,
  }) {
    final coordinates = Float32List(surface.textureCoordinates.length);
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    for (var i = 0; i < coordinates.length; i += 2) {
      coordinates[i] = surface.textureCoordinates[i] * imageWidth;
      coordinates[i + 1] = surface.textureCoordinates[i + 1] * imageHeight;
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      surface.positions,
      textureCoordinates: coordinates,
      colors: surface.colors,
      indices: indices,
    );
    final paint = Paint()
      ..shader = ui.ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.medium,
      )
      ..colorFilter = colorFilter;
    canvas.drawVertices(vertices, BlendMode.modulate, paint);
    vertices.dispose();
  }

  void _paintLeafEdge(Canvas canvas, PageCurlSurface surface) {
    if (surface.leadingEdge.length < 2 || surface.lift <= 0.01) {
      return;
    }
    final opacity = _leafOpacity;
    final path = Path()..addPolygon(surface.leadingEdge, false);
    canvas
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = scene.paperEdge.withValues(alpha: 0.75 * opacity),
      )
      ..drawPath(
        path.shift(Offset(scene.pivotOnLeft ? -1 : 1, -0.6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = scene.paper.withValues(alpha: 0.55 * opacity),
      );
  }

  static ColorFilter _washTowards(Color paper, double keep) {
    final r = paper.r * 255;
    final g = paper.g * 255;
    final b = paper.b * 255;
    final rest = 1 - keep;
    return ColorFilter.matrix(<double>[
      keep, 0, 0, 0, rest * r, //
      0, keep, 0, 0, rest * g, //
      0, 0, keep, 0, rest * b, //
      0, 0, 0, 1, 0, //
    ]);
  }

  @override
  bool shouldRepaint(PageTurnPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.scene != scene;
}
