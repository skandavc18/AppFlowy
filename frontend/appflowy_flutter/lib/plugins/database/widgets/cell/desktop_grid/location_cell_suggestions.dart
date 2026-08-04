import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/location_picker_card.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:flutter/material.dart';

/// Offers places under a cell that holds one.
///
/// The list is drawn in the overlay rather than inline: a grid cell is a
/// clipped box a row high, so anything laid out beside the field would be cut
/// off at its own edge.
class LocationCellSuggestions extends StatefulWidget {
  const LocationCellSuggestions({
    super.key,
    required this.viewId,
    required this.fieldId,
    required this.controller,
    required this.focusNode,
    required this.child,
  });

  final String viewId;
  final String fieldId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget child;

  @override
  State<LocationCellSuggestions> createState() =>
      _LocationCellSuggestionsState();
}

class _LocationCellSuggestionsState extends State<LocationCellSuggestions> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _anchor = GlobalKey();

  @override
  void dispose() {
    if (_portal.isShowing) {
      _portal.hide();
    }
    super.dispose();
  }

  void _pick(MapSuggestion suggestion) => _write(suggestion.value);

  void _pin(LatLng point) => _write(point.label);

  void _write(String value) {
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.focusNode.unfocus();
  }

  void _reveal({required bool show}) {
    if (show == _portal.isShowing) {
      return;
    }
    // Showing an overlay is a mutation, and what to show is only known while
    // the field is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || show == _portal.isShowing) {
        return;
      }
      show ? _portal.show() : _portal.hide();
    });
  }

  /// Where the card fits, given how much room the cell has around it.
  ///
  /// A cell can sit anywhere — the last row of a grid, the bottom of a
  /// calendar popover — so the card has to be told to open upwards, and to
  /// step back from the right edge, rather than being drawn off the window.
  _PickerPlacement _placementOf(BuildContext context) {
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    final window = MediaQuery.sizeOf(context);
    if (box == null || !box.hasSize) {
      return const _PickerPlacement(
        anchor: Alignment.bottomLeft,
        follower: Alignment.topLeft,
        offset: Offset(0, 4),
        maxHeight: LocationPickerMetrics.maxHeight,
      );
    }
    final origin = box.localToGlobal(Offset.zero);
    const margin = 12.0;
    final below = window.height - origin.dy - box.size.height - margin;
    final above = origin.dy - margin;
    final opensUp = below < LocationPickerMetrics.minHeight && above > below;
    final room = (opensUp ? above : below).clamp(
      LocationPickerMetrics.minHeight,
      LocationPickerMetrics.maxHeight,
    );

    // The card is anchored on the cell's left edge, so it only has to be
    // pulled back when its own width would run past the window.
    final overflow = origin.dx + LocationPickerMetrics.width + margin;
    final dx = overflow > window.width ? window.width - overflow : 0.0;

    return _PickerPlacement(
      anchor: opensUp ? Alignment.topLeft : Alignment.bottomLeft,
      follower: opensUp ? Alignment.bottomLeft : Alignment.topLeft,
      offset: Offset(dx, opensUp ? -4 : 4),
      maxHeight: room,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: LocationFieldRegistry.instance.listenable(widget.viewId),
      builder: (context, locationFields, child) {
        if (!locationFields.contains(widget.fieldId)) {
          _reveal(show: false);
          return child!;
        }
        return MapSuggestionBox(
          controller: widget.controller,
          focusNode: widget.focusNode,
          openOnFocus: true,
          builder: (context, status) {
            _reveal(show: status.open);
            return CompositedTransformTarget(
              key: _anchor,
              link: _link,
              child: OverlayPortal(
                controller: _portal,
                // The overlay lays its child out at the window's own size, so
                // the card has to be let out of those constraints or it grows
                // to fill the screen.
                overlayChildBuilder: (context) {
                  final placement = _placementOf(context);
                  return Align(
                    alignment: Alignment.topLeft,
                    child: CompositedTransformFollower(
                      link: _link,
                      targetAnchor: placement.anchor,
                      followerAnchor: placement.follower,
                      offset: placement.offset,
                      child: LocationPickerCard(
                        palette: mapPaletteOf(context),
                        status: status,
                        text: widget.controller.text,
                        maxHeight: placement.maxHeight,
                        onPicked: _pick,
                        onPinned: _pin,
                        onFreeText: _write,
                      ),
                    ),
                  );
                },
                child: child,
              ),
            );
          },
        );
      },
      child: widget.child,
    );
  }
}

/// Where a picker card was decided to go.
class _PickerPlacement {
  const _PickerPlacement({
    required this.anchor,
    required this.follower,
    required this.offset,
    required this.maxHeight,
  });

  final Alignment anchor;
  final Alignment follower;
  final Offset offset;
  final double maxHeight;
}
