import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/table_views/property_values.dart';
import 'package:appflowy/shared/table_views/row_media.dart';
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
    this.viewId = '',
    this.rowId = '',
  });

  final TableProperty property;
  final TableViewPalette palette;

  /// Whether this row is the one being read. Anything expensive — a map, a
  /// picture — is only worth building for what is actually in front of you.
  final bool live;

  final bool showLabel;

  /// A tighter cut, for a card that has little room.
  final bool compact;

  /// Which row this cell belongs to.
  ///
  /// A media cell reads as its file names alone, so without knowing the cell
  /// it came from the pictures behind it cannot be fetched — and a picture
  /// column then draws as an empty box. A view that leaves these blank simply
  /// keeps the older, wordier reading.
  final String viewId;
  final String rowId;

  bool get _canReadMedia =>
      property.isMedia && viewId.isNotEmpty && rowId.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final body = switch (property.kind) {
      TablePropertyKind.number => _number(),
      TablePropertyKind.progress => _progress(context),
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
        PropertyLabel(
          name: property.name,
          icon: tablePropertyGlyph(property.kind),
          ink: palette,
        ),
        const SizedBox(height: 7),
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
          fontWeight: FontWeight.w500,
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

  Widget _link() => PropertyLink(value: property.value, ink: palette);

  // ----------------------------------------------------------------- values

  Widget _number() => Text(
        property.value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 18 : 26,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: palette.textPrimary,
        ),
      );

  Widget _rating() => PropertyStars(marks: property.rating ?? 0, ink: palette);

  Widget _progress(BuildContext context) => PropertyProgress(
        value: property.value,
        fraction: property.fraction,
        ink: palette,
        compact: compact,
      );

  Widget _checkbox() => PropertyCheck(
        ticked: const ['yes', 'true', '1', 'checked']
            .contains(property.value.trim().toLowerCase()),
        ink: palette,
      );

  Widget _date() => Text(
        property.value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: palette.textPrimary,
        ),
      );

  // ------------------------------------------------------------------- sets

  Widget _badge() => PropertyPill(
        label: property.value,
        colour: palette.swatchFor(property.value),
        ink: palette,
        dense: compact,
      );

  Widget _tags() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final part in tablePartsOf(property.value))
            PropertyPill(
              label: part,
              colour: palette.swatchFor(part),
              ink: palette,
              dense: compact,
            ),
        ],
      );

  Widget _people() => PropertyPeople(
        names: tablePartsOf(property.value),
        initialsOf: tableInitialsOf,
        ink: palette,
      );

  Widget _relation() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final name in tablePartsOf(property.value))
            PropertyChip(
              label: name,
              icon: Icons.description_rounded,
              ink: palette,
            ),
        ],
      );

  Widget _files() {
    if (_canReadMedia) {
      return _mediaCell();
    }
    return PropertyFiles(
      names: [
        for (final name in tablePartsOf(property.value)) tableFileNameOf(name),
      ],
      ink: palette,
    );
  }

  /// A media cell drawn from what it actually holds. The files arrive a
  /// moment after the row does, so the box keeps its place meanwhile.
  Widget _mediaCell() => PropertyMedia(
        viewId: viewId,
        fieldId: property.fieldId,
        rowId: rowId,
        ink: palette,
        live: live,
        height: _pictureHeight,
      );

  double get _pictureHeight => compact
      ? TableViewMetrics.imagePreviewHeight * 0.7
      : TableViewMetrics.imagePreviewHeight;

  // --------------------------------------------------------------- pictures

  Widget _image() {
    if (_canReadMedia) {
      return _mediaCell();
    }
    final pictures =
        tablePartsOf(property.value).where(looksLikeTableImage).toList();
    return PropertyPictures(
      sources: pictures.isEmpty ? [property.value.trim()] : pictures,
      ink: palette,
      live: live,
      height: _pictureHeight,
    );
  }

  Widget _location() => PropertyMap(
        pinId: property.fieldId,
        value: property.value,
        ink: palette,
        live: live,
        height: TableViewMetrics.mapPreviewHeight,
        compact: compact,
      );
}

/// The mark a property's name wears, after the kind of value it holds.
IconData tablePropertyGlyph(TablePropertyKind kind) => switch (kind) {
      TablePropertyKind.text => Icons.text_fields_rounded,
      TablePropertyKind.excerpt => Icons.notes_rounded,
      TablePropertyKind.number => Icons.numbers_rounded,
      TablePropertyKind.rating => Icons.star_rounded,
      TablePropertyKind.progress => Icons.speed_rounded,
      TablePropertyKind.checkbox => Icons.check_box_rounded,
      TablePropertyKind.badge => Icons.arrow_drop_down_circle_rounded,
      TablePropertyKind.tags => Icons.label_rounded,
      TablePropertyKind.date => Icons.calendar_today_rounded,
      TablePropertyKind.person => Icons.person_rounded,
      TablePropertyKind.image => Icons.image_rounded,
      TablePropertyKind.files => Icons.attach_file_rounded,
      TablePropertyKind.location => Icons.place_rounded,
      TablePropertyKind.relation => Icons.hub_rounded,
      TablePropertyKind.link => Icons.link_rounded,
    };

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

/// The cover a row wears, drawn the way its own page draws it.
class TableCoverView extends StatelessWidget {
  const TableCoverView({
    super.key,
    required this.cover,
    required this.palette,
  });

  final TableCover cover;
  final PropertyInk palette;

  @override
  Widget build(BuildContext context) {
    switch (cover.kind) {
      case TableCoverKind.picture:
        return TablePicture(url: cover.value, palette: palette);
      case TableCoverKind.asset:
        return Image.asset(
          PageStyleCoverImageType.builtInImagePath(cover.value),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              PropertyPicturePlaceholder(ink: palette),
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

/// A picture from wherever the table keeps it.
class TablePicture extends StatelessWidget {
  const TablePicture({
    super.key,
    required this.url,
    required this.palette,
    this.fit = BoxFit.cover,
  });

  final String url;
  final PropertyInk palette;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) =>
      PropertyPicture(url: url, ink: palette, fit: fit);
}
