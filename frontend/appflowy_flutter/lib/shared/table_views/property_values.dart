import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/progress_bar.dart';
import 'package:appflowy/shared/table_views/property_ink.dart';
import 'package:appflowy/shared/table_views/row_media.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

export 'property_ink.dart';

/// The leaves every view of a table draws a row's values with.
///
/// A slide, a gallery card and a timeline entry show the same columns, so a
/// picture, a place or a bar is drawn here once and looks the same in each.

const double _mosaicGap = 3;

/// A property's name, with a mark saying what kind of value follows.
class PropertyLabel extends StatelessWidget {
  const PropertyLabel({
    super.key,
    required this.name,
    required this.icon,
    required this.ink,
  });

  final String name;
  final IconData icon;
  final PropertyInk ink;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkspaceGlyph(icon, size: 14, color: ink.textMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
              color: ink.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// A rounded window for pictures and maps, its edge only just stated.
class PropertyFrame extends StatelessWidget {
  const PropertyFrame({
    super.key,
    required this.ink,
    required this.child,
    this.height,
    this.radius = 14,
  });

  final PropertyInk ink;
  final Widget child;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(radius);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: corners,
          // An inner edge as quiet as a photograph's, so pale map tiles still
          // end somewhere without the window reading as a drawn box.
          border: Border.all(
            color: ink.textPrimary.withValues(alpha: ink.isDark ? 0.1 : 0.07),
          ),
        ),
        child: ClipRRect(
          borderRadius: corners,
          child: ColoredBox(color: ink.surface, child: child),
        ),
      ),
    );
  }
}

/// What stands in a picture's place while it is on its way, or when it cannot
/// be had at all.
class PropertyPicturePlaceholder extends StatelessWidget {
  const PropertyPicturePlaceholder({
    super.key,
    required this.ink,
    this.glyphSize = 26,
    this.icon = Icons.image_rounded,
  });

  final PropertyInk ink;
  final double glyphSize;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ink.raised,
            Color.alphaBlend(
              ink.textMuted.withValues(alpha: ink.isDark ? 0.12 : 0.08),
              ink.raised,
            ),
          ],
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: 0.6,
          child: WorkspaceGlyph(
            icon,
            size: glyphSize,
            color: ink.textMuted,
          ),
        ),
      ),
    );
  }
}

/// A picture from a link or a file on this machine, faded in over its
/// placeholder once it has arrived.
class PropertyPicture extends StatelessWidget {
  const PropertyPicture({
    super.key,
    required this.url,
    required this.ink,
    this.fit = BoxFit.cover,
    this.glyphSize = 26,
  });

  final String url;
  final PropertyInk ink;
  final BoxFit fit;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = PropertyPicturePlaceholder(
      ink: ink,
      glyphSize: glyphSize,
    );
    final provider = _providerOf(url.trim());
    if (provider == null) {
      return placeholder;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder,
        Image(
          image: provider,
          fit: fit,
          isAntiAlias: true,
          frameBuilder: (context, child, frame, synchronous) => synchronous
              ? child
              : AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: child,
                ),
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  static ImageProvider? _providerOf(String source) {
    if (source.isEmpty) {
      return null;
    }
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return NetworkImage(source);
    }
    if (source.startsWith('file://')) {
      return FileImage(File(Uri.parse(source).toFilePath()));
    }
    return FileImage(File(source));
  }
}

/// Several pictures in one frame: the first large, the next two beside it,
/// and a count of whatever else there is.
class PropertyMosaic extends StatelessWidget {
  const PropertyMosaic({
    super.key,
    required this.count,
    required this.tileBuilder,
    required this.ink,
    required this.height,
  });

  final int count;

  /// Draws one picture; [small] says it is one of the side tiles.
  final Widget Function(BuildContext context, int index, bool small)
      tileBuilder;
  final PropertyInk ink;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    Widget tile(int index, {bool small = false}) =>
        tileBuilder(context, index, small);

    final Widget content;
    if (count == 1) {
      content = tile(0);
    } else if (count == 2) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: tile(0)),
          const SizedBox(width: _mosaicGap),
          Expanded(child: tile(1)),
        ],
      );
    } else {
      final more = count - 3;
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: tile(0)),
          const SizedBox(width: _mosaicGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tile(1, small: true)),
                const SizedBox(height: _mosaicGap),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      tile(2, small: true),
                      if (more > 0)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Center(
                            child: Text(
                              '+$more',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return PropertyFrame(ink: ink, height: height, child: content);
  }
}

/// Pictures named by links or paths.
class PropertyPictures extends StatelessWidget {
  const PropertyPictures({
    super.key,
    required this.sources,
    required this.ink,
    required this.live,
    required this.height,
  });

  final List<String> sources;
  final PropertyInk ink;

  /// Pictures are only fetched for what is actually being looked at.
  final bool live;
  final double height;

  @override
  Widget build(BuildContext context) {
    return PropertyMosaic(
      count: sources.length,
      ink: ink,
      height: height,
      tileBuilder: (context, index, small) => live
          ? PropertyPicture(
              url: sources[index],
              ink: ink,
              glyphSize: small ? 16 : 26,
            )
          : PropertyPicturePlaceholder(ink: ink, glyphSize: small ? 16 : 26),
    );
  }
}

/// A media cell drawn from the files it actually holds rather than from their
/// names: pictures in a mosaic, everything else as file tiles.
class PropertyMedia extends StatelessWidget {
  const PropertyMedia({
    super.key,
    required this.viewId,
    required this.fieldId,
    required this.rowId,
    required this.ink,
    required this.live,
    required this.height,
  });

  final String viewId;
  final String fieldId;
  final String rowId;
  final PropertyInk ink;
  final bool live;
  final double height;

  @override
  Widget build(BuildContext context) {
    return RowMediaView(
      viewId: viewId,
      fieldId: fieldId,
      rowId: rowId,
      builder: (context, files) {
        if (files == null) {
          // Keeps its place while the cell is read, so nothing jumps after.
          return PropertyFrame(
            ink: ink,
            height: height,
            child: PropertyPicturePlaceholder(ink: ink),
          );
        }
        final pictures = files.where((file) => file.isImage).toList();
        final rest = files.where((file) => !file.isImage).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pictures.isNotEmpty)
              PropertyMosaic(
                count: pictures.length,
                ink: ink,
                height: height,
                tileBuilder: (context, index, small) {
                  final placeholder = PropertyPicturePlaceholder(
                    ink: ink,
                    glyphSize: small ? 16 : 26,
                  );
                  if (!live) {
                    return placeholder;
                  }
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      placeholder,
                      RowMediaImage(
                        file: pictures[index],
                        placeholder: const SizedBox.shrink(),
                      ),
                    ],
                  );
                },
              ),
            if (rest.isNotEmpty) ...[
              if (pictures.isNotEmpty) const SizedBox(height: 8),
              PropertyFiles(
                names: [for (final file in rest) file.name],
                ink: ink,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Files, each with the mark of its own kind.
class PropertyFiles extends StatelessWidget {
  const PropertyFiles({super.key, required this.names, required this.ink});

  final List<String> names;
  final PropertyInk ink;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final name in names) PropertyFileTile(name: name, ink: ink),
      ],
    );
  }
}

/// One file: its kind's mark, its name, and its extension in small capitals.
class PropertyFileTile extends StatelessWidget {
  const PropertyFileTile({super.key, required this.name, required this.ink});

  final String name;
  final PropertyInk ink;

  @override
  Widget build(BuildContext context) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 && dot < name.length - 1
        ? name.substring(dot + 1).toUpperCase()
        : '';
    return _Tile(
      ink: ink,
      children: [
        WorkspaceGlyph.file(name),
        const SizedBox(width: 7),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              stem,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: ink.textPrimary,
              ),
            ),
          ),
        ),
        if (extension.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            extension,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: ink.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// A named thing a row points at, such as a related page.
class PropertyChip extends StatelessWidget {
  const PropertyChip({
    super.key,
    required this.label,
    required this.icon,
    required this.ink,
  });

  final String label;
  final IconData icon;
  final PropertyInk ink;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      ink: ink,
      children: [
        WorkspaceGlyph(icon, size: 16, color: ink.accent),
        const SizedBox(width: 6),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: ink.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.ink, required this.children});

  final PropertyInk ink;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 5, 10, 5),
      decoration: BoxDecoration(
        color: ink.raised,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// A status or a tag: a dot of its colour and its name on a wash of it.
class PropertyPill extends StatelessWidget {
  const PropertyPill({
    super.key,
    required this.label,
    required this.colour,
    required this.ink,
    this.dense = false,
  });

  final String label;
  final Color colour;
  final PropertyInk ink;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final text = ink.isDark
        ? Color.lerp(colour, Colors.white, 0.5)!
        : Color.lerp(colour, Colors.black, 0.38)!;
    return Container(
      padding: EdgeInsets.fromLTRB(
        dense ? 7 : 8,
        dense ? 2 : 3.5,
        dense ? 9 : 11,
        dense ? 2 : 3.5,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: ink.isDark ? 0.22 : 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 11.5 : 12,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Somebody, with their initials on a disc of their own colour.
class PropertyAvatar extends StatelessWidget {
  const PropertyAvatar({
    super.key,
    required this.name,
    required this.initials,
    required this.ink,
    this.size = 26,
  });

  final String name;
  final String initials;
  final PropertyInk ink;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colour = ink.swatchFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(colour, Colors.white, 0.2)!,
            Color.lerp(colour, Colors.black, 0.12)!,
          ],
        ),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// People, each with their avatar.
class PropertyPeople extends StatelessWidget {
  const PropertyPeople({
    super.key,
    required this.names,
    required this.initialsOf,
    required this.ink,
  });

  final List<String> names;
  final String Function(String name) initialsOf;
  final PropertyInk ink;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final name in names)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PropertyAvatar(
                name: name,
                initials: initialsOf(name),
                ink: ink,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ink.textPrimary,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// How far along something is: the bar, and the figure beside it.
class PropertyProgress extends StatelessWidget {
  const PropertyProgress({
    super.key,
    required this.value,
    required this.fraction,
    required this.ink,
    this.compact = false,
  });

  final String value;
  final double? fraction;
  final PropertyInk ink;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = ProgressBarColors.of(context);
    final label = progressDisplayLabel(value);
    final fraction = this.fraction;
    final complete = fraction != null && fraction >= 1;
    return Semantics(
      value: label,
      child: ExcludeSemantics(
        child: Row(
          children: [
            if (fraction != null) ...[
              Expanded(
                child: AppFlowyProgressBar(
                  fraction: fraction,
                  fill: colors.fill,
                  highlight: colors.highlight,
                  track: colors.track,
                  height: compact ? 6 : 8,
                ),
              ),
              SizedBox(width: compact ? 8 : 12),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 72 : 110),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12 : 13.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: complete ? colors.ink : ink.textPrimary,
                ),
              ),
            ),
            if (complete) ...[
              const SizedBox(width: 5),
              WorkspaceGlyph(
                Icons.check_circle_rounded,
                size: compact ? 13 : 15,
                color: colors.ink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A yes or a no.
class PropertyCheck extends StatelessWidget {
  const PropertyCheck({super.key, required this.ticked, required this.ink});

  final bool ticked;
  final PropertyInk ink;

  @override
  Widget build(BuildContext context) {
    final done = ProgressBarColors.of(context).ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ticked)
          WorkspaceGlyph(Icons.check_circle_rounded, size: 19, color: done)
        else
          Container(
            width: 17,
            height: 17,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: ink.textMuted.withValues(alpha: 0.55),
                width: 1.5,
              ),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          ticked ? LocaleKeys.button_yes.tr() : LocaleKeys.button_no.tr(),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: ticked ? FontWeight.w600 : FontWeight.w400,
            color: ticked ? ink.textPrimary : ink.textMuted,
          ),
        ),
      ],
    );
  }
}

/// A link, read as where it goes: the site first, the rest quieter.
class PropertyLink extends StatelessWidget {
  const PropertyLink({super.key, required this.value, required this.ink});

  final String value;
  final PropertyInk ink;

  @override
  Widget build(BuildContext context) {
    final (site, rest) = splitPropertyLink(value);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: site,
            style: TextStyle(fontWeight: FontWeight.w600, color: ink.accent),
          ),
          if (rest.isNotEmpty)
            TextSpan(text: rest, style: TextStyle(color: ink.textMuted)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13.5),
    );
  }
}

/// The site a link goes to, and the path within it.
(String, String) splitPropertyLink(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) {
    return (trimmed, '');
  }
  final site = uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
  var rest = uri.path == '/' ? '' : uri.path;
  if (uri.hasQuery) {
    rest += '?${uri.query}';
  }
  return (site, rest);
}

/// Up to five marks, filled for each point earned.
class PropertyStars extends StatelessWidget {
  const PropertyStars({super.key, required this.marks, required this.ink});

  final int marks;
  final PropertyInk ink;

  static const _gold = Color(0xFFF2A626);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: i < marks
                ? const WorkspaceGlyph(
                    Icons.star_rounded,
                    size: 17,
                    color: _gold,
                  )
                : WorkspaceGlyph(
                    Icons.star_outline_rounded,
                    size: 17,
                    color: ink.textMuted.withValues(alpha: 0.45),
                    role: WorkspaceGlyphRole.preserveInk,
                  ),
          ),
      ],
    );
  }
}

/// A place: a small live map with its name floating on it, or just the name
/// while the place has not been found yet.
class PropertyMap extends StatelessWidget {
  const PropertyMap({
    super.key,
    required this.pinId,
    required this.value,
    required this.ink,
    required this.live,
    required this.height,
    this.compact = false,
  });

  final String pinId;
  final String value;
  final PropertyInk ink;

  /// Only the value being looked at draws a live map.
  final bool live;
  final double height;

  /// A tight cut keeps to the name alone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final place = parseMapLocation(value);
    final point =
        place.point ?? GeocodeCache.instance.peek(geocodeKeyFor(place))?.point;
    final label = place.label.isEmpty ? value.trim() : place.label;
    if (point == null || compact) {
      return _PlaceLine(label: label, ink: ink, maxLines: compact ? 1 : 2);
    }
    return PropertyFrame(
      ink: ink,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (live)
            AppMapView(
              pins: [AppMapPin(id: pinId, point: point, title: label)],
              initialCenter: point,
              initialZoom: 13.5,
              showControls: false,
              showPopup: false,
              clustering: false,
              autoFit: false,
            )
          else
            _MapPlaceholder(ink: ink),
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            // The top corner is clear of the map's credits along the bottom.
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topLeft,
                child: _PlaceChip(label: label, ink: ink),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceLine extends StatelessWidget {
  const _PlaceLine({
    required this.label,
    required this.ink,
    required this.maxLines,
  });

  final String label;
  final PropertyInk ink;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkspaceGlyph(Icons.place_rounded, size: 16, color: ink.accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              color: ink.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceChip extends StatelessWidget {
  const _PlaceChip({required this.label, required this.ink});

  final String label;
  final PropertyInk ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 11, 4),
      decoration: BoxDecoration(
        color: ink.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: ink.shadow.withValues(alpha: ink.isDark ? 0.4 : 0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceGlyph(Icons.place_rounded, size: 15, color: ink.accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a map will be, before it is worth drawing one.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({required this.ink});

  final PropertyInk ink;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _GridPainter(
        ink.textMuted.withValues(alpha: ink.isDark ? 0.12 : 0.09),
      ),
      child: PropertyPicturePlaceholder(
        ink: ink,
        glyphSize: 24,
        icon: Icons.map_rounded,
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1;
    const step = 22.0;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.colour != colour;
}
