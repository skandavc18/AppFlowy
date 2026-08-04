import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';

/// Draws one column of one row in the shape it earned.
///
/// Every branch here is a leaf: it takes a value that has already been read
/// and a palette, and returns something to look at. Deciding WHICH branch is
/// somebody else's job, which is what keeps this free of rules and lets every
/// view of a table render a column identically.
class TablePropertyView extends StatelessWidget {
  const TablePropertyView({
    super.key,
    required this.property,
    required this.palette,
    this.live = false,
    this.showLabel = true,
    this.compact = false,
  });

  final TableProperty property;
  final TableViewPalette palette;

  /// Whether this row is the one being read. Anything expensive — a map, a
  /// picture — is only worth building for what is actually in front of you.
  final bool live;

  final bool showLabel;

  /// A tighter cut, for a card that has little room.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final body = switch (property.kind) {
      TablePropertyKind.number => _number(),
      TablePropertyKind.progress => _progress(),
      TablePropertyKind.checkbox => _checkbox(),
      TablePropertyKind.badge => _badge(),
      TablePropertyKind.tags => _tags(),
      TablePropertyKind.date => _date(),
      TablePropertyKind.person => _people(),
      TablePropertyKind.image => _image(),
      TablePropertyKind.files => _files(),
      TablePropertyKind.location => _location(),
      TablePropertyKind.relation => _relation(),
      TablePropertyKind.link => _link(),
      TablePropertyKind.rating => _rating(),
      TablePropertyKind.excerpt => _excerpt(),
      TablePropertyKind.text => _text(),
    };

    if (!showLabel) {
      return body;
    }

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
        maxLines: compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 13 : 14,
          height: 1.35,
          color: palette.textPrimary,
        ),
      );

  Widget _excerpt() => Text(
        property.value,
        maxLines: compact ? 2 : 4,
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
          fontSize: compact ? 18 : 28,
          height: 1.05,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
          color: palette.textPrimary,
        ),
      );

  Widget _rating() {
    final marks = property.rating ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(
              i < marks ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 16,
              color: i < marks
                  ? palette.accent
                  : palette.textMuted.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }

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
            borderRadius:
                BorderRadius.circular(TableViewMetrics.progressHeight),
            child: SizedBox(
              height: TableViewMetrics.progressHeight,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: palette.textMuted.withValues(alpha: 0.18),
                      ),
                    ),
                    AnimatedContainer(
                      duration: TableViewMetrics.change,
                      curve: TableViewMetrics.settleCurve,
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
          duration: TableViewMetrics.hover,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color:
                ticked ? palette.accent : palette.accent.withValues(alpha: 0),
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

  Widget _badge() => TablePill(
        label: property.value,
        colour: palette.swatchFor(property.value),
        palette: palette,
      );

  Widget _tags() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final part in tablePartsOf(property.value))
            TablePill(
              label: part,
              colour: palette.swatchFor(part),
              palette: palette,
            ),
        ],
      );

  Widget _people() => Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          for (final name in tablePartsOf(property.value))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TableAvatar(name: name, palette: palette),
                const SizedBox(width: 7),
                Text(
                  name,
                  style: TextStyle(fontSize: 13, color: palette.textPrimary),
                ),
              ],
            ),
        ],
      );

  Widget _relation() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final name in tablePartsOf(property.value))
            _chip(Icons.link_rounded, name, palette.textMuted),
        ],
      );

  Widget _files() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final name in tablePartsOf(property.value))
            _chip(
              fileIconForName(tableFileNameOf(name)),
              tableFileNameOf(name),
              palette.accent,
            ),
        ],
      );

  Widget _chip(IconData icon, String label, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(TableViewMetrics.pillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: tint),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: palette.textPrimary),
              ),
            ),
          ],
        ),
      );

  // --------------------------------------------------------------- pictures

  Widget _image() {
    final source = tablePartsOf(property.value)
        .firstWhere(looksLikeTableImage, orElse: () => property.value.trim());
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: compact
            ? TableViewMetrics.imagePreviewHeight * 0.7
            : TableViewMetrics.imagePreviewHeight,
        width: double.infinity,
        child: live
            ? TablePicture(url: source, palette: palette)
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
        if (point != null && live && !compact)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: TableViewMetrics.mapPreviewHeight,
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
        else if (point != null && !compact)
          Container(
            height: TableViewMetrics.mapPreviewHeight,
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        if (point != null && !compact) const SizedBox(height: 8),
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
}

/// The name at the end of a path or a link.
String tableFileNameOf(String value) {
  final path = value.split('?').first;
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty || parts.last.isEmpty ? value : parts.last;
}

/// A coloured label — a status, a tag, a group heading.
class TablePill extends StatelessWidget {
  const TablePill({
    super.key,
    required this.label,
    required this.colour,
    required this.palette,
    this.dense = false,
  });

  final String label;
  final Color colour;
  final TableViewPalette palette;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: palette.isDark ? 0.26 : 0.14),
        borderRadius: BorderRadius.circular(TableViewMetrics.pillRadius),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: palette.isDark
              ? Color.lerp(colour, Colors.white, 0.45)
              : Color.lerp(colour, Colors.black, 0.35),
        ),
      ),
    );
  }
}

/// Somebody, with their initials standing in for a picture.
class TableAvatar extends StatelessWidget {
  const TableAvatar({
    super.key,
    required this.name,
    required this.palette,
    this.size = TableViewMetrics.avatarSize,
  });

  final String name;
  final TableViewPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.swatchFor(name).withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
      child: Text(
        tableInitialsOf(name),
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// A picture from wherever the table keeps it.
/// The cover a row wears, drawn the way its own page draws it.
class TableCoverView extends StatelessWidget {
  const TableCoverView({
    super.key,
    required this.cover,
    required this.palette,
  });

  final TableCover cover;
  final TableViewPalette palette;

  @override
  Widget build(BuildContext context) {
    switch (cover.kind) {
      case TableCoverKind.picture:
        return TablePicture(url: cover.value, palette: palette);
      case TableCoverKind.asset:
        return Image.asset(
          PageStyleCoverImageType.builtInImagePath(cover.value),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ColoredBox(color: palette.raised),
        );
      case TableCoverKind.colour:
        return ColoredBox(
          color: FlowyTint.fromId(cover.value)?.color(context) ??
              _colourOf(cover.value) ??
              palette.raised,
        );
      case TableCoverKind.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: FlowyGradientColor.fromId(cover.value).linear,
          ),
        );
    }
  }
}

/// A colour cover is stored as a tint name or as a packed ARGB string.
Color? _colourOf(String value) {
  final digits = value.replaceFirst('0x', '').replaceFirst('#', '');
  final packed = int.tryParse(digits, radix: 16);
  if (packed == null) {
    return null;
  }
  return Color(digits.length <= 6 ? packed | 0xFF000000 : packed);
}

class TablePicture extends StatelessWidget {
  const TablePicture({
    super.key,
    required this.url,
    required this.palette,
    this.fit = BoxFit.cover,
  });

  final String url;
  final TableViewPalette palette;
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
