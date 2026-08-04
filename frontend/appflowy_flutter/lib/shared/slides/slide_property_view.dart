import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:flutter/material.dart';

/// Draws one column of one row in the shape it earned.
///
/// Every branch here is a leaf: it takes a value that has already been read
/// and a palette, and returns something to look at. Deciding WHICH branch is
/// somebody else's job, which is what keeps this file free of rules.
class SlidePropertyView extends StatelessWidget {
  const SlidePropertyView({
    super.key,
    required this.property,
    required this.palette,
    this.live = false,
  });

  final SlideProperty property;
  final SlidePalette palette;

  /// Whether this slide is the one being read. Anything expensive — a map, a
  /// picture — is only worth building for the slide in front.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final body = switch (property.kind) {
      SlidePropertyKind.number => _number(),
      SlidePropertyKind.progress => _progress(),
      SlidePropertyKind.checkbox => _checkbox(),
      SlidePropertyKind.badge => _badge(),
      SlidePropertyKind.tags => _tags(),
      SlidePropertyKind.date => _date(),
      SlidePropertyKind.person => _people(),
      SlidePropertyKind.image => _image(),
      SlidePropertyKind.files => _files(),
      SlidePropertyKind.location => _location(),
      SlidePropertyKind.relation => _relation(),
      SlidePropertyKind.link => _link(),
      SlidePropertyKind.excerpt => _excerpt(),
      SlidePropertyKind.text => _text(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          property.name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            height: 1.1,
            letterSpacing: 0.7,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        body,
      ],
    );
  }

  // ------------------------------------------------------------------ words

  Widget _text() => Text(
        property.value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: palette.textPrimary,
        ),
      );

  Widget _excerpt() => Text(
        property.value,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.55,
          color: palette.textSecondary,
        ),
      );

  Widget _link() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_rounded, size: 14, color: palette.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              property.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: palette.accent,
                decoration: TextDecoration.underline,
                decorationColor: palette.accent.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      );

  // ----------------------------------------------------------------- values

  Widget _number() => Text(
        property.value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 28,
          height: 1.05,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
          color: palette.textPrimary,
        ),
      );

  Widget _progress() {
    final fraction = property.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          property.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        if (fraction != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(SlideMetrics.progressHeight),
            child: SizedBox(
              height: SlideMetrics.progressHeight,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: palette.textMuted.withValues(alpha: 0.18),
                      ),
                    ),
                    AnimatedContainer(
                      duration: SlideMetrics.change,
                      curve: SlideMetrics.settleCurve,
                      width: constraints.maxWidth * fraction,
                      color: palette.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _checkbox() {
    final ticked = const ['yes', 'true', '1', 'checked']
        .contains(property.value.trim().toLowerCase());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: SlideMetrics.hover,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: ticked ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: ticked
                  ? palette.accent
                  : palette.textMuted.withValues(alpha: 0.5),
              width: 1.4,
            ),
          ),
          child: ticked
              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 8),
        Text(
          ticked ? 'Yes' : 'No',
          style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
        ),
      ],
    );
  }

  Widget _date() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 13,
            color: palette.textMuted,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              property.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                letterSpacing: 0.1,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      );

  // ------------------------------------------------------------------- sets

  Widget _badge() => _pill(property.value, palette.swatchFor(property.value));

  Widget _tags() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final part in slidePartsOf(property.value))
            _pill(part, palette.swatchFor(part)),
        ],
      );

  Widget _pill(String label, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: palette.isDark ? 0.26 : 0.14),
          borderRadius: BorderRadius.circular(SlideMetrics.badgeRadius),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: palette.isDark
                ? Color.lerp(colour, Colors.white, 0.45)
                : Color.lerp(colour, Colors.black, 0.35),
          ),
        ),
      );

  Widget _people() => Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          for (final name in slidePartsOf(property.value))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: SlideMetrics.avatarSize,
                  height: SlideMetrics.avatarSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.swatchFor(name).withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    slideInitialsOf(name),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
        ],
      );

  Widget _relation() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final name in slidePartsOf(property.value))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(SlideMetrics.badgeRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 13,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _files() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final name in slidePartsOf(property.value))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(SlideMetrics.badgeRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    fileIconForName(_fileNameOf(name)),
                    size: 14,
                    color: palette.accent,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      _fileNameOf(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  // --------------------------------------------------------------- pictures

  Widget _image() {
    final source = slidePartsOf(property.value)
        .firstWhere(looksLikeSlideImage, orElse: () => property.value.trim());
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: SlideMetrics.imagePreviewHeight,
        width: double.infinity,
        child: live
            ? SlidePicture(url: source, palette: palette)
            : ColoredBox(color: palette.raised),
      ),
    );
  }

  Widget _location() {
    final place = parseMapLocation(property.value);
    final point =
        place.point ?? GeocodeCache.instance.peek(geocodeKeyFor(place))?.point;
    final label = place.label.isEmpty ? property.value : place.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (point != null && live)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: SlideMetrics.mapPreviewHeight,
              width: double.infinity,
              child: AppMapView(
                pins: [
                  AppMapPin(id: property.fieldId, point: point, title: label),
                ],
                initialCenter: point,
                initialZoom: 13.5,
                showControls: false,
                clustering: false,
                autoFit: false,
              ),
            ),
          )
        else if (point != null)
          Container(
            height: SlideMetrics.mapPreviewHeight,
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        if (point != null) const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.place_rounded, size: 14, color: palette.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _fileNameOf(String value) {
    final path = value.split('?').first;
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty || parts.last.isEmpty ? value : parts.last;
  }
}

/// A picture from wherever the table keeps it.
class SlidePicture extends StatelessWidget {
  const SlidePicture({
    super.key,
    required this.url,
    required this.palette,
    this.fit = BoxFit.cover,
  });

  final String url;
  final SlidePalette palette;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return ColoredBox(color: palette.raised);
    }
    final placeholder = ColoredBox(color: palette.raised);
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        fit: fit,
        isAntiAlias: true,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    return Image.file(
      File(trimmed),
      fit: fit,
      isAntiAlias: true,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
