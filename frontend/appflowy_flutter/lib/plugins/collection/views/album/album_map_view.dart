import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/collection/views/album/album_context_menu.dart';
import 'package:appflowy/plugins/collection/views/album/album_host.dart';
import 'package:appflowy/plugins/collection/views/album/album_lightbox.dart';
import 'package:appflowy/plugins/collection/views/album/album_thumbnail.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_places.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where the album was made, read from the GPS each camera wrote into the
/// picture.
///
/// AppFlowy ships no map tiles and works offline, so this plots the pictures
/// on a graticule rather than pretending to be a street map — and hands off
/// to a real map when a place is worth looking at properly.
class AlbumMapView extends StatelessWidget {
  const AlbumMapView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) {
    return AlbumHost(
      collection: collection,
      builder: (context, controller, palette) {
        final places = _placesOf(controller);
        return AlbumScaffold(
          controller: controller,
          palette: palette,
          padded: false,
          leading: [
            if (places.isNotEmpty)
              Text(
                places.length == 1
                    ? LocaleKeys.collections_album_onePlace.tr()
                    : LocaleKeys.collections_album_placeCount
                        .tr(args: ['${places.length}']),
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
          ],
          trailing: [
            if (controller.isReadingMetadata)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: palette.textMuted,
                ),
              ),
          ],
          child: places.isEmpty
              ? AlbumEmptyState(
                  palette: palette,
                  icon: Icons.location_off_rounded,
                  title: controller.isReadingMetadata
                      ? LocaleKeys.collections_album_readingMetadata.tr()
                      : LocaleKeys.collections_album_noPlaces.tr(),
                  description:
                      LocaleKeys.collections_album_noPlacesDescription.tr(),
                )
              : _Places(
                  controller: controller,
                  palette: palette,
                  places: places,
                  parentViewId: collection.collectionView.id,
                  onOpenInWorkspace: (item) => collection.onOpen(item.view),
                ),
        );
      },
    );
  }

  List<AlbumPlace> _placesOf(AlbumController controller) {
    final points = <AlbumPlacePoint>[];
    for (final item in controller.ordered) {
      final exif = controller.metadataFor(item).exif;
      if (!exif.hasLocation) {
        continue;
      }
      points.add(
        AlbumPlacePoint(
          item: item,
          latitude: exif.latitude!,
          longitude: exif.longitude!,
        ),
      );
    }
    return clusterAlbumPlaces(points);
  }
}

class _Places extends StatefulWidget {
  const _Places({
    required this.controller,
    required this.palette,
    required this.places,
    required this.parentViewId,
    required this.onOpenInWorkspace,
  });

  final AlbumController controller;
  final CollectionPalette palette;
  final List<AlbumPlace> places;
  final String parentViewId;
  final ValueChanged<AlbumMediaItem> onOpenInWorkspace;

  @override
  State<_Places> createState() => _PlacesState();
}

class _PlacesState extends State<_Places> {
  int selected = 0;

  @override
  void didUpdateWidget(covariant _Places oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selected >= widget.places.length) {
      selected = 0;
    }
  }

  AlbumPlace get place => widget.places[selected.clamp(
        0,
        widget.places.length - 1,
      )];

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) => showAlbumBackgroundMenu(
              context: context,
              globalPosition: details.globalPosition,
              controller: widget.controller,
              palette: palette,
              parentViewId: widget.parentViewId,
              showTileSize: false,
              onSlideshow: () {},
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AlbumMetrics.gutter,
                16,
                AlbumMetrics.gutter,
                8,
              ),
              child: _WorldPlot(
                places: widget.places,
                palette: palette,
                selected: selected,
                onSelect: (index) => setState(() => selected = index),
              ),
            ),
          ),
        ),
        Container(
          height: 172,
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border(
              top: BorderSide(
                color: palette.border.withValues(alpha: 0.35),
                width: 0.6,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AlbumMetrics.gutter,
            12,
            AlbumMetrics.gutter,
            14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.place_rounded,
                    size: 15,
                    color: palette.accent,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    place.label,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    place.count == 1
                        ? LocaleKeys.collections_album_onePhoto.tr()
                        : LocaleKeys.collections_album_itemCount
                            .tr(args: ['${place.count}']),
                    style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                  ),
                  const Spacer(),
                  AlbumToolbarButton(
                    palette: palette,
                    icon: Icons.content_copy_rounded,
                    tooltip: LocaleKeys.collections_album_copyCoordinates.tr(),
                    onPressed: () => _copy(place),
                  ),
                  AlbumToolbarButton(
                    palette: palette,
                    icon: Icons.map_rounded,
                    tooltip: LocaleKeys.collections_album_openInMaps.tr(),
                    onPressed: () => _openInMaps(place),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: place.items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AlbumMetrics.spacing),
                  itemBuilder: (context, index) {
                    final item = place.items[index];
                    return SizedBox(
                      width: 108,
                      child: GestureDetector(
                        onTap: () => showAlbumLightbox(
                          context: context,
                          controller: widget.controller,
                          palette: palette,
                          startId: item.id,
                          onOpenInWorkspace: widget.onOpenInWorkspace,
                        ),
                        onSecondaryTapDown: (details) => showAlbumItemMenu(
                          context: context,
                          globalPosition: details.globalPosition,
                          controller: widget.controller,
                          palette: palette,
                          item: item,
                          onOpen: () => showAlbumLightbox(
                            context: context,
                            controller: widget.controller,
                            palette: palette,
                            startId: item.id,
                            onOpenInWorkspace: widget.onOpenInWorkspace,
                          ),
                          onOpenInfo: () => showAlbumLightbox(
                            context: context,
                            controller: widget.controller,
                            palette: palette,
                            startId: item.id,
                            startWithInfo: true,
                            onOpenInWorkspace: widget.onOpenInWorkspace,
                          ),
                          onSlideshowFromHere: () => showAlbumLightbox(
                            context: context,
                            controller: widget.controller,
                            palette: palette,
                            startId: item.id,
                            startSlideshow: true,
                            onOpenInWorkspace: widget.onOpenInWorkspace,
                          ),
                          onOpenInWorkspace: widget.onOpenInWorkspace,
                        ),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AlbumThumbnail(
                            item: item,
                            palette: palette,
                            decodeWidth: 140,
                            radius: 8,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _copy(AlbumPlace place) async {
    await Clipboard.setData(ClipboardData(text: place.label));
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(LocaleKeys.collections_album_coordinatesCopied.tr()),
        ),
      );
    }
  }

  Future<void> _openInMaps(AlbumPlace place) async {
    final latitude = place.latitude;
    final longitude = place.longitude;
    await launchUrl(
      Uri.parse(
        'https://www.openstreetmap.org/?mlat=$latitude&mlon=$longitude'
        '#map=13/$latitude/$longitude',
      ),
      mode: LaunchMode.externalApplication,
    );
  }
}

class _WorldPlot extends StatelessWidget {
  const _WorldPlot({
    required this.places,
    required this.palette,
    required this.selected,
    required this.onSelect,
  });

  final List<AlbumPlace> places;
  final CollectionPalette palette;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Equirectangular, so a pin's position is simply its coordinates.
        final size = _plotSize(constraints.biggest);
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _selectNearest(details.localPosition, size),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border, width: 0.6),
                ),
                child: CustomPaint(
                  painter: _WorldPlotPainter(
                    places: places,
                    selected: selected,
                    grid: palette.border,
                    accent: palette.accent,
                    ink: palette.textPrimary,
                    surface: palette.surface,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Size _plotSize(Size available) {
    if (!available.isFinite || available.isEmpty) {
      return const Size(720, 360);
    }
    final width = math.min(available.width, available.height * 2);
    return Size(width, width / 2);
  }

  void _selectNearest(Offset position, Size size) {
    var best = double.infinity;
    var index = selected;
    for (var i = 0; i < places.length; i++) {
      final point = _project(places[i], size);
      final distance = (point - position).distance;
      if (distance < best) {
        best = distance;
        index = i;
      }
    }
    if (best <= 36) {
      onSelect(index);
    }
  }
}

Offset _project(AlbumPlace place, Size size) => Offset(
      (place.longitude + 180) / 360 * size.width,
      (90 - place.latitude) / 180 * size.height,
    );

class _WorldPlotPainter extends CustomPainter {
  const _WorldPlotPainter({
    required this.places,
    required this.selected,
    required this.grid,
    required this.accent,
    required this.ink,
    required this.surface,
  });

  final List<AlbumPlace> places;
  final int selected;
  final Color grid;
  final Color accent;
  final Color ink;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = grid.withValues(alpha: 0.5);

    for (var longitude = -180; longitude <= 180; longitude += 30) {
      final x = (longitude + 180) / 360 * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var latitude = -90; latitude <= 90; latitude += 30) {
      final y = (90 - latitude) / 180 * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    // The equator and the prime meridian anchor the plot.
    final anchor = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = grid;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      anchor,
    );
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      anchor,
    );

    final maximum =
        places.fold<int>(1, (value, place) => math.max(value, place.count));
    for (var index = 0; index < places.length; index++) {
      final place = places[index];
      final centre = _project(place, size);
      final weight = math.sqrt(place.count / maximum);
      final radius = 5 + weight * 9;
      final isSelected = index == selected;
      canvas.drawCircle(
        centre,
        radius + 3,
        Paint()..color = accent.withValues(alpha: isSelected ? 0.26 : 0.12),
      );
      canvas.drawCircle(centre, radius, Paint()..color = accent);
      if (isSelected) {
        canvas.drawCircle(
          centre,
          radius + 5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = ink.withValues(alpha: 0.55),
        );
      }
      if (place.count > 1) {
        final painter = TextPainter(
          text: TextSpan(
            text: '${place.count}',
            style: TextStyle(
              color: surface,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          centre - Offset(painter.width / 2, painter.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WorldPlotPainter oldDelegate) =>
      oldDelegate.places != places ||
      oldDelegate.selected != selected ||
      oldDelegate.accent != accent;
}
