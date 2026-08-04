import 'dart:ui' as ui;

import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:flutter/material.dart';

/// One control on the map.
class MapControlButton extends StatefulWidget {
  const MapControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.palette,
    this.onPressed,
    this.selected = false,
    this.size = MapMetrics.controlSize,
  });

  final IconData icon;
  final String tooltip;
  final MapPalette palette;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;

  @override
  State<MapControlButton> createState() => _MapControlButtonState();
}

class _MapControlButtonState extends State<MapControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.onPressed != null;
    final tint = widget.selected
        ? palette.accent
        : enabled
            ? palette.textPrimary
            : palette.textMuted.withValues(alpha: 0.5);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 420),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: MapMetrics.hover,
            curve: Curves.easeOutCubic,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MapMetrics.controlRadius - 2),
              color: widget.selected
                  ? palette.accent.withValues(alpha: 0.14)
                  // Fading from the hover colour at zero alpha keeps the tween
                  // in one hue; transparent black would flash grey.
                  : palette.hover
                      .withValues(alpha: _hovered && enabled ? 1 : 0),
            ),
            child: Icon(widget.icon, size: 17.5, color: tint),
          ),
        ),
      ),
    );
  }
}

/// A floating cluster of controls, the way both Google and Apple stack them.
class MapControlGroup extends StatelessWidget {
  const MapControlGroup({
    super.key,
    required this.children,
    required this.palette,
    this.axis = Axis.vertical,
  });

  final List<Widget> children;
  final MapPalette palette;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final divided = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        divided.add(
          Container(
            width: axis == Axis.vertical ? MapMetrics.controlSize : 1,
            height: axis == Axis.vertical ? 1 : MapMetrics.controlSize,
            color: palette.border.withValues(alpha: 0.5),
          ),
        );
      }
      divided.add(children[index]);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MapMetrics.controlGroupRadius),
        boxShadow: palette.chromeShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MapMetrics.controlGroupRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: palette.floating
                  .withValues(alpha: palette.isDark ? 0.9 : 0.93),
              border: Border.all(
                color: palette.border.withValues(alpha: 0.5),
                width: 0.8,
              ),
              borderRadius:
                  BorderRadius.circular(MapMetrics.controlGroupRadius),
            ),
            child: axis == Axis.vertical
                ? Column(mainAxisSize: MainAxisSize.min, children: divided)
                : Row(mainAxisSize: MainAxisSize.min, children: divided),
          ),
        ),
      ),
    );
  }
}

/// Everything a person needs to drive the map, stacked down its right edge.
class AppMapToolbar extends StatelessWidget {
  const AppMapToolbar({
    super.key,
    required this.palette,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetView,
    this.onLocate,
    this.onFullscreen,
    this.onLayers,
    this.isFullscreen = false,
    this.canZoomIn = true,
    this.canZoomOut = true,
    this.zoomInLabel = 'Zoom in',
    this.zoomOutLabel = 'Zoom out',
    this.resetLabel = 'Reset view',
    this.locateLabel = 'Locate me',
    this.layersLabel = 'Map style',
    this.fullscreenLabel = 'Full screen',
  });

  final MapPalette palette;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetView;
  final VoidCallback? onLocate;
  final VoidCallback? onFullscreen;
  final VoidCallback? onLayers;
  final bool isFullscreen;
  final bool canZoomIn;
  final bool canZoomOut;
  final String zoomInLabel;
  final String zoomOutLabel;
  final String resetLabel;
  final String locateLabel;
  final String layersLabel;
  final String fullscreenLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        MapControlGroup(
          palette: palette,
          children: [
            MapControlButton(
              icon: Icons.add_rounded,
              tooltip: zoomInLabel,
              palette: palette,
              onPressed: canZoomIn ? onZoomIn : null,
            ),
            MapControlButton(
              icon: Icons.remove_rounded,
              tooltip: zoomOutLabel,
              palette: palette,
              onPressed: canZoomOut ? onZoomOut : null,
            ),
          ],
        ),
        const SizedBox(height: MapMetrics.controlGap),
        MapControlGroup(
          palette: palette,
          children: [
            MapControlButton(
              icon: Icons.explore_rounded,
              tooltip: resetLabel,
              palette: palette,
              onPressed: onResetView,
            ),
            if (onLocate != null)
              MapControlButton(
                icon: Icons.my_location_rounded,
                tooltip: locateLabel,
                palette: palette,
                onPressed: onLocate,
              ),
          ],
        ),
        if (onLayers != null || onFullscreen != null) ...[
          const SizedBox(height: MapMetrics.controlGap),
          MapControlGroup(
            palette: palette,
            children: [
              if (onLayers != null)
                MapControlButton(
                  icon: Icons.layers_rounded,
                  tooltip: layersLabel,
                  palette: palette,
                  onPressed: onLayers,
                ),
              if (onFullscreen != null)
                MapControlButton(
                  icon: isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  tooltip: fullscreenLabel,
                  palette: palette,
                  onPressed: onFullscreen,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The search box that floats over the top left of the map.
class AppMapSearchField extends StatefulWidget {
  const AppMapSearchField({
    super.key,
    required this.palette,
    required this.onSubmitted,
    this.onChanged,
    this.onPicked,
    this.suggestPins,
    this.hintText = 'Search this map',
    this.busy = false,
  });

  final MapPalette palette;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;

  /// A place chosen from the list instead of typed out in full.
  final ValueChanged<MapSuggestion>? onPicked;

  /// Rows already on the map that match what is being typed.
  final List<MapSuggestion> Function(String query)? suggestPins;

  final String hintText;
  final bool busy;

  @override
  State<AppMapSearchField> createState() => _AppMapSearchFieldState();
}

class _AppMapSearchFieldState extends State<AppMapSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _pick(MapSuggestion suggestion) {
    _controller.text = suggestion.title;
    _focus.unfocus();
    widget.onPicked?.call(suggestion);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MapSuggestionBox(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.onPicked != null,
      extra: widget.suggestPins,
      builder: (context, status) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildField(),
          if (status.suggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            MapSuggestionList(
              palette: widget.palette,
              suggestions: status.suggestions,
              onPicked: _pick,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField() {
    final palette = widget.palette;
    return Container(
      width: MapMetrics.searchWidth,
      height: MapMetrics.searchHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MapMetrics.controlGroupRadius),
        boxShadow: palette.chromeShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MapMetrics.controlGroupRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: palette.floating
                  .withValues(alpha: palette.isDark ? 0.9 : 0.93),
              border: Border.all(
                color: palette.border.withValues(alpha: 0.5),
                width: 0.8,
              ),
              borderRadius:
                  BorderRadius.circular(MapMetrics.controlGroupRadius),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    onSubmitted: widget.onSubmitted,
                    onChanged: widget.onChanged,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      color: palette.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hoverColor: Colors.transparent,
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
                if (widget.busy)
                  SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: palette.textMuted,
                    ),
                  )
                else if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _controller.clear();
                      widget.onChanged?.call('');
                      widget.onSubmitted('');
                      setState(() {});
                    },
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line of credit the tile licence asks for.
class MapAttribution extends StatelessWidget {
  const MapAttribution({
    super.key,
    required this.text,
    required this.palette,
  });

  final String text;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.floating.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          height: 1.2,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
