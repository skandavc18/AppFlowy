import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// How wide and tall the place picker is allowed to be.
abstract final class LocationPickerMetrics {
  static const double width = 316;
  static const double mapHeight = 138;
  static const double listMaxHeight = 214;
  static const double radius = 12;

  /// The tallest the whole card is ever drawn.
  static const double maxHeight = 396;

  /// Below this there is no room worth opening downwards into.
  static const double minHeight = 210;
}

/// The card that drops out of a location cell.
///
/// It is a place picker rather than a list of strings: the map shows what has
/// been chosen and a click on it pins somewhere no search would have found.
class LocationPickerCard extends StatelessWidget {
  const LocationPickerCard({
    super.key,
    required this.palette,
    required this.status,
    required this.text,
    required this.onPicked,
    required this.onPinned,
    required this.onFreeText,
    this.maxHeight = LocationPickerMetrics.maxHeight,
    this.width = LocationPickerMetrics.width,
  });

  final MapPalette palette;
  final MapSuggestionStatus status;

  /// Whatever is currently in the cell.
  final String text;

  /// How tall the card may be where it is being opened.
  final double maxHeight;

  /// How wide to draw. A form gives it the measure of the page.
  final double width;

  final ValueChanged<MapSuggestion> onPicked;
  final ValueChanged<LatLng> onPinned;
  final ValueChanged<String> onFreeText;

  /// The height of the "click the map to pin" strip.
  static const double _stripHeight = 27;

  LatLng? get _pinned {
    final typed = parseMapLocation(text).point;
    if (typed != null) {
      return typed;
    }
    return status.suggestions
        .where((suggestion) => suggestion.point.isValid)
        .map((suggestion) => suggestion.point)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final pinned = _pinned;
    // The map is what gives way when the card is short: a list with one row
    // showing is useless, whereas a smaller map still reads.
    final mapHeight = (LocationPickerMetrics.mapHeight -
            (LocationPickerMetrics.maxHeight - maxHeight) * 0.45)
        .clamp(76.0, LocationPickerMetrics.mapHeight);
    final listHeight =
        (maxHeight - mapHeight - _stripHeight).clamp(96.0, maxHeight);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: palette.floating,
        borderRadius: BorderRadius.circular(LocationPickerMetrics.radius),
        border: Border.all(
          color: palette.border.withValues(alpha: 0.5),
          width: 0.8,
        ),
        boxShadow: palette.popupShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: mapHeight,
            child: AppMapView(
              key: const ValueKey('location-cell-map'),
              pins: pinned == null
                  ? const []
                  : [AppMapPin(id: 'picked', point: pinned, title: text)],
              apiKey: MapsSettings.instance.apiKey,
              initialCenter: pinned,
              initialZoom: pinned == null ? 2.2 : 14,
              showControls: false,
              showPopup: false,
              clustering: false,
              autoFit: pinned != null,
              onPointTap: onPinned,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: palette.hover.withValues(alpha: 0.35),
            child: Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 13, color: palette.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    LocaleKeys.map_pinFromMap.tr(),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          MapSuggestionList(
            palette: palette,
            suggestions: status.suggestions,
            onPicked: onPicked,
            width: width,
            maxHeight: listHeight,
            framed: false,
            busy: status.busy,
            hint: LocaleKeys.map_locationCellHint.tr(),
            freeText: text.trim(),
            onFreeText: onFreeText,
          ),
        ],
      ),
    );
  }
}
