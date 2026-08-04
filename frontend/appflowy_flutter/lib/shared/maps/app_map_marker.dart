import 'dart:math' as math;

import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';

/// Draws one pin, or the bubble standing for several.
///
/// Markers are widgets rather than paint because clustering has already cut
/// what is on screen down to a hundred or so — few enough to animate properly,
/// and few enough that each can wear the application's own colours and icons.
class AppMapMarker extends StatelessWidget {
  const AppMapMarker({
    super.key,
    required this.cluster,
    required this.palette,
    this.selected = false,
    this.hovered = false,
    this.dimmed = false,
    this.onTap,
    this.onEnter,
    this.onExit,
    this.onSecondaryTap,
  });

  final MapCluster cluster;
  final MapPalette palette;
  final bool selected;
  final bool hovered;

  /// Set while a search is running and this is not one of the matches.
  final bool dimmed;

  final VoidCallback? onTap;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  final VoidCallback? onSecondaryTap;

  /// How big the whole thing is, so the view can place it by its point.
  static Size sizeOf(MapCluster cluster) {
    if (cluster.isSingle) {
      return const Size(MapMetrics.markerWidth, MapMetrics.markerHeight);
    }
    final side = clusterDiameter(cluster.count);
    return Size(side, side);
  }

  /// A bubble grows with what is in it, but only slowly — a hundred pins must
  /// not swallow the map.
  static double clusterDiameter(int count) {
    final grown = MapMetrics.clusterMin + math.log(count) * 7.5;
    return grown.clamp(MapMetrics.clusterMin, MapMetrics.clusterMax);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onEnter?.call(),
      onExit: (_) => onExit?.call(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onSecondaryTap: onSecondaryTap,
        child: TweenAnimationBuilder<double>(
          // The key on the marker changes when a group re-forms, so each new
          // marker plays its own drop rather than sliding from the last one.
          tween: Tween(begin: 0, end: 1),
          duration: MapMetrics.drop,
          curve: MapMetrics.dropCurve,
          builder: (context, dropped, child) {
            return Opacity(
              opacity: dropped.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - dropped) * -22),
                child: child,
              ),
            );
          },
          child: AnimatedScale(
            scale: selected ? MapMetrics.selectedScale : 1,
            duration: MapMetrics.hover,
            curve: Curves.easeOutCubic,
            child: AnimatedSlide(
              offset: Offset(0, hovered ? -MapMetrics.hoverLift / 38 : 0),
              duration: MapMetrics.hover,
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: dimmed ? 0.32 : 1,
                duration: MapMetrics.hover,
                child: cluster.isSingle
                    ? _Pin(
                        pin: cluster.first,
                        palette: palette,
                        selected: selected,
                        hovered: hovered,
                      )
                    : _Bubble(
                        cluster: cluster,
                        palette: palette,
                        hovered: hovered,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({
    required this.pin,
    required this.palette,
    required this.selected,
    required this.hovered,
  });

  final AppMapPin pin;
  final MapPalette palette;
  final bool selected;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final fill = pin.color ??
        (pin.status.isNotEmpty
            ? palette.swatchFor(pin.status)
            : palette.swatchFor(pin.title));
    final ring = selected ? palette.accent : Colors.white;

    return SizedBox(
      width: MapMetrics.markerWidth,
      height: MapMetrics.markerHeight,
      child: CustomPaint(
        painter: _PinPainter(
          fill: fill,
          ring: ring,
          shadow:
              palette.shadow.withValues(alpha: palette.isDark ? 0.55 : 0.28),
          lifted: hovered || selected,
        ),
        child: Align(
          alignment: const Alignment(0, -0.42),
          child: _Badge(pin: pin, size: MapMetrics.markerIcon),
        ),
      ),
    );
  }
}

/// What goes inside a pin: the row's own icon, or the first letter of its name.
class _Badge extends StatelessWidget {
  const _Badge({required this.pin, required this.size});

  final AppMapPin pin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = pin.icon;
    if (icon != null && icon.isNotEmpty) {
      return Text(
        icon,
        style: TextStyle(fontSize: size * 0.92, height: 1),
        textAlign: TextAlign.center,
      );
    }
    final initial = pin.title.trim().isEmpty
        ? '·'
        : String.fromCharCode(pin.title.trim().runes.first).toUpperCase();
    return Text(
      initial,
      style: TextStyle(
        fontSize: size * 0.86,
        height: 1,
        color: Colors.white,
        fontWeight: FontWeight.w700,
        shadows: const [
          Shadow(color: Color(0x33000000), blurRadius: 1, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// The marker's body: a rounded tile standing on a small point, which reads as
/// a place without looking like a stock map pin.
class _PinPainter extends CustomPainter {
  const _PinPainter({
    required this.fill,
    required this.ring,
    required this.shadow,
    required this.lifted,
  });

  final Color fill;
  final Color ring;
  final Color shadow;
  final bool lifted;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyHeight = size.height - MapMetrics.markerTail;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, bodyHeight),
      const Radius.circular(MapMetrics.markerRadius),
    );

    final tail = Path()
      ..moveTo(size.width / 2 - 5.5, bodyHeight - 1)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 5.5, bodyHeight - 1)
      ..close();

    final outline = Path()
      ..addRRect(body)
      ..addPath(tail, Offset.zero);

    canvas.drawShadow(outline, shadow, lifted ? 5 : 3, false);

    canvas.drawPath(
      outline,
      Paint()
        ..color = ring
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    final inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        MapMetrics.markerBorder,
        MapMetrics.markerBorder,
        size.width - MapMetrics.markerBorder * 2,
        bodyHeight - MapMetrics.markerBorder * 2,
      ),
      const Radius.circular(MapMetrics.markerRadius - 2),
    );
    final innerTail = Path()
      ..moveTo(size.width / 2 - 3.6, bodyHeight - MapMetrics.markerBorder)
      ..lineTo(size.width / 2, size.height - 3.2)
      ..lineTo(size.width / 2 + 3.6, bodyHeight - MapMetrics.markerBorder)
      ..close();

    final paint = Paint()..isAntiAlias = true;
    // A little vertical shading keeps the tile from reading as a flat sticker.
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(fill, Colors.white, 0.16)!,
        fill,
      ],
    ).createShader(inner.outerRect);

    canvas
      ..drawRRect(inner, paint)
      ..drawPath(innerTail, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_PinPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.ring != ring ||
      oldDelegate.shadow != shadow ||
      oldDelegate.lifted != lifted;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.cluster,
    required this.palette,
    required this.hovered,
  });

  final MapCluster cluster;
  final MapPalette palette;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final side = AppMapMarker.clusterDiameter(cluster.count);
    final fill = palette.accent;
    return SizedBox(
      width: side,
      height: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // The soft ring is what makes a cluster read as "several", the way
          // every map does it, without a hard second outline.
          color: fill.withValues(alpha: hovered ? 0.32 : 0.24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MapMetrics.clusterRing / 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              boxShadow: palette.markerShadow,
              border: Border.all(color: Colors.white, width: 1.6),
            ),
            child: Center(
              child: Text(
                cluster.count > 999 ? '999+' : '${cluster.count}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: side < 40 ? 12 : 13.5,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  fontVariations: flowyFontVariationsForWeight(FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
