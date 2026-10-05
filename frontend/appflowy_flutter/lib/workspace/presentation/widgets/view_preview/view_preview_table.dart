import 'dart:math' as math;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/extension.dart';
import 'package:appflowy/util/field_type_extension.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_find_projection.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart'
    show FieldType;
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';

/// Every preview of a table — gallery cards, embeds, the search palette —
/// draws it here, the way its grid does: saved column widths, field icons,
/// tags and checkboxes. The grid is drawn at its own size and only scaled
/// down a little; what does not fit runs on under the right and bottom
/// edges instead of being squeezed until no cell can be read.
class ViewPreviewTable extends StatelessWidget {
  const ViewPreviewTable({
    super.key,
    required this.snapshot,
    this.surface,
    this.padding = const EdgeInsets.all(16),
    this.minimumScale = 0.75,
    this.maximumScale = 0.9,
  });

  final FolderGalleryDatabaseSnapshot snapshot;

  /// What the table sits on. Defaults to the gallery card's preview sheet.
  final Color? surface;

  /// Leading, top and trailing margins around a table that fits. A larger
  /// table may run on into the trailing margin and is cut by the edge itself;
  /// a long table always runs on to the bottom edge, so no bottom inset is kept.
  final EdgeInsets padding;
  final double minimumScale;
  final double maximumScale;

  /// A column nobody resized is as wide as a new grid column.
  static const defaultColumnWidth = 150.0;
  static const _minimumColumnWidth = 64.0;
  static const _maximumColumnWidth = 320.0;
  static const _cellPadding = 10.0;
  static const _bodyFontSize = 14.0;
  static const _headerFontSize = 13.0;
  static const _radius = 8.0;
  static const _rightFade = 32.0;
  static const _bottomFade = 28.0;

  @override
  Widget build(BuildContext context) {
    final columnCount = snapshot.columns.length;
    if (columnCount == 0) return const SizedBox.shrink();
    final textScaler = MediaQuery.textScalerOf(context);
    final rowHeight =
        math.max(36.0, textScaler.scale(_bodyFontSize) * 1.3 + 16);
    final natural = [
      for (var column = 0; column < columnCount; column++)
        (snapshot.widthAt(column) ?? defaultColumnWidth)
            .clamp(_minimumColumnWidth, _maximumColumnWidth)
            .toDouble(),
    ];
    final naturalWidth = natural.fold<double>(0, (sum, width) => sum + width);
    final naturalHeight = rowHeight * (snapshot.rows.length + 1);
    final continues = snapshot.totalRowCount > snapshot.rows.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }
        // A tiny thumbnail keeps proportionally smaller margins.
        final left = math.min(padding.left, width * 0.08);
        final right = math.min(padding.right, width * 0.08);
        final top = math.min(padding.top, height * 0.08);
        final inner = math.max(1.0, width - left - right);
        final scale = (inner / naturalWidth)
            .clamp(minimumScale, math.max(minimumScale, maximumScale))
            .toDouble();
        final fitsWidth = naturalWidth * scale <= inner + 0.5;
        // A table narrower than the space spans it, every column widened in
        // proportion, so the room goes to text rather than to one last column.
        final tableWidth = fitsWidth ? inner / scale : naturalWidth;
        final widths = [
          for (final column in natural) column * tableWidth / naturalWidth,
        ];

        // A larger table may use the trailing margins before the edge cuts it;
        // a fade then marks only an edge that really cuts rows or columns.
        final drawnWidth = tableWidth * scale;
        final drawnHeight = naturalHeight * scale;
        final visibleWidth = math.max(1.0, math.min(drawnWidth, width - left));
        final visibleHeight =
            math.max(1.0, math.min(drawnHeight, height - top));
        final cutRight = drawnWidth > visibleWidth + 0.5;
        final cutBottom = drawnHeight > visibleHeight + 0.5;
        Widget table = ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: _PreviewGrid(
                snapshot: snapshot,
                widths: widths,
                rowHeight: rowHeight,
                surface: surface ?? GalleryCardPalette.previewSurface(context),
              ),
            ),
          ),
        );
        if (cutRight) {
          table = _fade(
            table,
            Alignment.centerLeft,
            Alignment.centerRight,
            math.min(_rightFade, visibleWidth * 0.2) / visibleWidth,
          );
        }
        if (cutBottom || continues) {
          table = _fade(
            table,
            Alignment.topCenter,
            Alignment.bottomCenter,
            math.min(_bottomFade, visibleHeight * 0.25) / visibleHeight,
          );
        }
        return Padding(
          padding: EdgeInsets.only(left: left, top: top),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: visibleWidth,
              height: visibleHeight,
              child: table,
            ),
          ),
        );
      },
    );
  }

  static Widget _fade(
    Widget child,
    Alignment begin,
    Alignment end,
    double extent,
  ) =>
      ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: begin,
          end: end,
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 1 - extent.clamp(0.0, 1.0), 1],
        ).createShader(bounds),
        child: child,
      );
}

/// The grid at its own size: header, then one line per row.
class _PreviewGrid extends StatelessWidget {
  const _PreviewGrid({
    required this.snapshot,
    required this.widths,
    required this.rowHeight,
    required this.surface,
  });

  final FolderGalleryDatabaseSnapshot snapshot;
  final List<double> widths;
  final double rowHeight;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final tags = Theme.of(context).extension<AFThemeExtension>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = palette.textPrimary;
    final tableSurface = Color.alphaBlend(
      ink.withValues(alpha: ink.a * (dark ? 0.035 : 0.012)),
      surface,
    );
    final headerSurface = Color.alphaBlend(
      ink.withValues(alpha: ink.a * (dark ? 0.065 : 0.035)),
      tableSurface,
    );
    final rule = ink.withValues(alpha: ink.a * (dark ? 0.13 : 0.1));
    final frame = ink.withValues(alpha: ink.a * (dark ? 0.16 : 0.13));
    final radius = BorderRadius.circular(ViewPreviewTable._radius);
    final width = widths.fold<double>(0, (sum, width) => sum + width);
    return SizedBox(
      width: width,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: frame),
        ),
        child: DecoratedBox(
          key: const ValueKey('folder-gallery-database-grid'),
          decoration: BoxDecoration(color: tableSurface, borderRadius: radius),
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  key: const ValueKey('folder-gallery-database-header-row'),
                  decoration: BoxDecoration(
                    color: headerSurface,
                    border: Border(bottom: BorderSide(color: rule)),
                  ),
                  child: _line(
                    rule,
                    (column) => _HeaderCell(
                      name: snapshot.columns[column],
                      type: snapshot.typeAt(column),
                      palette: palette,
                    ),
                  ),
                ),
                for (var row = 0; row < snapshot.rows.length; row++)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: row == snapshot.rows.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: rule)),
                    ),
                    child: _line(
                      rule,
                      (column) => _BodyCell(
                        value: column < snapshot.rows[row].length
                            ? snapshot.rows[row][column]
                            : '',
                        type: snapshot.typeAt(column),
                        options: snapshot.optionsAt(row, column),
                        palette: palette,
                        tags: tags,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(Color rule, Widget Function(int column) cell) {
    Widget slot(int column) => DecoratedBox(
          decoration: BoxDecoration(
            border: column == 0 ? null : Border(left: BorderSide(color: rule)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ViewPreviewTable._cellPadding,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: cell(column),
            ),
          ),
        );
    final last = widths.length - 1;
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          for (var column = 0; column < last; column++)
            SizedBox(width: widths[column], child: slot(column)),
          // The last column takes what is left, so rounding never overflows.
          Expanded(child: slot(last)),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.name,
    required this.type,
    required this.palette,
  });

  final String name;
  final FieldType? type;
  final FolderExplorerPalette palette;

  static const _iconTypes = {
    FieldType.RichText,
    FieldType.Number,
    FieldType.DateTime,
    FieldType.SingleSelect,
    FieldType.MultiSelect,
    FieldType.Checkbox,
    FieldType.URL,
    FieldType.Checklist,
    FieldType.LastEditedTime,
    FieldType.CreatedTime,
    FieldType.Relation,
    FieldType.Summary,
    FieldType.Time,
    FieldType.Translate,
    FieldType.Media,
  };

  @override
  Widget build(BuildContext context) {
    final type = this.type;
    return Row(
      children: [
        if (type != null && _iconTypes.contains(type)) ...[
          FlowySvg(
            type.svgData,
            size: const Size.square(16),
            color: palette.textSecondary,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: FolderGalleryFindText(
            text: name,
            child: Text(
              name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontFamily: 'Inter',
                fontSize: ViewPreviewTable._headerFontSize,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.value,
    required this.type,
    required this.options,
    required this.palette,
    required this.tags,
  });

  final String value;
  final FieldType? type;
  final List<FolderGalleryTableOption> options;
  final FolderExplorerPalette palette;

  /// The theme's tag tints; absent outside the app theme.
  final AFThemeExtension? tags;

  /// Typed text a reader can find. A URL, count or icon is not cell text.
  static const _findableTypes = {
    FieldType.RichText,
    FieldType.Number,
    FieldType.Summary,
    FieldType.Translate,
    FieldType.SingleSelect,
    FieldType.MultiSelect,
    FieldType.Checklist,
    FieldType.DateTime,
    FieldType.CreatedTime,
    FieldType.LastEditedTime,
  };

  @override
  Widget build(BuildContext context) {
    final findable = _findableTypes.contains(type);
    if (type == FieldType.Checkbox) {
      return FlowySvg(
        value.isEmpty ? FlowySvgs.uncheck_s : FlowySvgs.check_filled_s,
        blendMode: BlendMode.dst,
        size: const Size.square(16),
      );
    }
    if (options.isNotEmpty) {
      return ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          minWidth: 0,
          maxWidth: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < options.length; index++) ...[
                if (index > 0) const SizedBox(width: 4),
                _Tag(
                  option: options[index],
                  findable: findable,
                  palette: palette,
                  tags: tags,
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (value.isEmpty) return const SizedBox.shrink();
    final color = switch (type) {
      FieldType.URL => palette.accent,
      FieldType.Relation || FieldType.Media => palette.textSecondary,
      _ => palette.textPrimary,
    };
    return FolderGalleryFindText(
      text: value,
      enabled: findable,
      child: Text(
        value,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontFamily: 'Inter',
          fontSize: ViewPreviewTable._bodyFontSize,
          height: 1.25,
        ),
      ),
    );
  }
}

/// A select option, tinted as its grid tag is.
class _Tag extends StatelessWidget {
  const _Tag({
    required this.option,
    required this.findable,
    required this.palette,
    required this.tags,
  });

  final FolderGalleryTableOption option;
  final bool findable;
  final FolderExplorerPalette palette;
  final AFThemeExtension? tags;

  @override
  Widget build(BuildContext context) {
    final theme = tags;
    final tint = theme == null
        ? Color.alphaBlend(
            palette.accent.withValues(alpha: 0.16),
            palette.surface,
          )
        : option.color.toColor(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: FolderGalleryFindText(
          text: option.name,
          enabled: findable,
          child: Text(
            option.name,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: theme?.textColor ?? palette.textPrimary,
              fontFamily: 'Inter',
              fontSize: 12.5,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}
