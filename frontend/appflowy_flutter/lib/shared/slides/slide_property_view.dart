import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/shared/table_views/property_values.dart';
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
    this.viewId = '',
    this.rowId = '',
  });

  final SlideProperty property;
  final SlidePalette palette;

  /// Whether this slide is the one being read. Anything expensive — a map, a
  /// picture — is only worth building for the slide in front.
  final bool live;

  /// The cell the value came from. A media column reads as its file names
  /// alone, so without these its pictures cannot be fetched.
  final String viewId;
  final String rowId;

  bool get _canReadMedia =>
      property.isMedia && viewId.isNotEmpty && rowId.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final body = switch (property.kind) {
      SlidePropertyKind.number => _number(),
      SlidePropertyKind.progress => PropertyProgress(
          value: property.value,
          fraction: property.fraction,
          ink: palette,
        ),
      SlidePropertyKind.checkbox => PropertyCheck(
          ticked: const ['yes', 'true', '1', 'checked']
              .contains(property.value.trim().toLowerCase()),
          ink: palette,
        ),
      SlidePropertyKind.badge => PropertyPill(
          label: property.value,
          colour: palette.swatchFor(property.value),
          ink: palette,
        ),
      SlidePropertyKind.tags => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final part in slidePartsOf(property.value))
              PropertyPill(
                label: part,
                colour: palette.swatchFor(part),
                ink: palette,
              ),
          ],
        ),
      SlidePropertyKind.date => _date(),
      SlidePropertyKind.person => PropertyPeople(
          names: slidePartsOf(property.value),
          initialsOf: slideInitialsOf,
          ink: palette,
        ),
      SlidePropertyKind.image => _pictures(),
      SlidePropertyKind.files => _files(),
      SlidePropertyKind.location => PropertyMap(
          pinId: property.fieldId,
          value: property.value,
          ink: palette,
          live: live,
          height: SlideMetrics.mapPreviewHeight,
        ),
      SlidePropertyKind.relation => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final name in slidePartsOf(property.value))
              PropertyChip(
                label: name,
                icon: Icons.description_rounded,
                ink: palette,
              ),
          ],
        ),
      SlidePropertyKind.link => PropertyLink(
          value: property.value,
          ink: palette,
        ),
      SlidePropertyKind.excerpt => _excerpt(),
      SlidePropertyKind.text => _text(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PropertyLabel(
          name: property.name,
          icon: slidePropertyGlyph(property.kind),
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
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14.5,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: palette.textPrimary,
        ),
      );

  Widget _excerpt() => Text(
        property.value,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.6,
          color: palette.textSecondary,
        ),
      );

  Widget _number() => Text(
        property.value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 26,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: palette.textPrimary,
        ),
      );

  Widget _date() => Text(
        property.value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: palette.textPrimary,
        ),
      );

  // --------------------------------------------------------------- pictures

  Widget _pictures() {
    if (_canReadMedia) {
      return _media();
    }
    final pictures =
        slidePartsOf(property.value).where(looksLikeSlideImage).toList();
    return PropertyPictures(
      sources: pictures.isEmpty ? [property.value.trim()] : pictures,
      ink: palette,
      live: live,
      height: SlideMetrics.imagePreviewHeight,
    );
  }

  Widget _files() {
    if (_canReadMedia) {
      return _media();
    }
    return PropertyFiles(
      names: [
        for (final part in slidePartsOf(property.value)) _fileNameOf(part),
      ],
      ink: palette,
    );
  }

  Widget _media() => PropertyMedia(
        viewId: viewId,
        fieldId: property.fieldId,
        rowId: rowId,
        ink: palette,
        live: live,
        height: SlideMetrics.imagePreviewHeight,
      );

  static String _fileNameOf(String value) {
    final path = value.split('?').first;
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty || parts.last.isEmpty ? value : parts.last;
  }
}

/// The mark a property's name wears, after the kind of value it holds.
IconData slidePropertyGlyph(SlidePropertyKind kind) => switch (kind) {
      SlidePropertyKind.text => Icons.text_fields_rounded,
      SlidePropertyKind.excerpt => Icons.notes_rounded,
      SlidePropertyKind.number => Icons.numbers_rounded,
      SlidePropertyKind.progress => Icons.speed_rounded,
      SlidePropertyKind.checkbox => Icons.check_box_rounded,
      SlidePropertyKind.badge => Icons.arrow_drop_down_circle_rounded,
      SlidePropertyKind.tags => Icons.label_rounded,
      SlidePropertyKind.date => Icons.calendar_today_rounded,
      SlidePropertyKind.person => Icons.person_rounded,
      SlidePropertyKind.image => Icons.image_rounded,
      SlidePropertyKind.files => Icons.attach_file_rounded,
      SlidePropertyKind.location => Icons.place_rounded,
      SlidePropertyKind.relation => Icons.hub_rounded,
      SlidePropertyKind.link => Icons.link_rounded,
    };
