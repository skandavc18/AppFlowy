import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/maps/app_map_toolbar.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_place_field.dart';
import 'package:appflowy/shared/maps/map_stage.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:appflowy/workspace/application/maps/map_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_picker_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MapBlockKeys {
  const MapBlockKeys._();

  static const String type = 'map';

  /// The table whose rows are placed, when the map is reading one.
  static const String viewId = 'view_id';

  /// How that table is placed.
  static const String spec = 'spec';

  /// Where the pin is, on a map with no table.
  static const String latitude = 'lat';
  static const String longitude = 'lng';

  /// Where that map was left looking. Kept apart from the pin so looking
  /// around never carries the pin along; maps saved before fall back to it.
  static const String viewLatitude = 'view_lat';
  static const String viewLongitude = 'view_lng';
  static const String zoom = 'zoom';

  /// What the pinned place is called.
  static const String place = 'place';

  static const String height = 'height';
  static const String width = 'width';
}

Node mapBlockNode({
  String viewId = '',
  double? latitude,
  double? longitude,
  double? zoom,
  String place = '',
  double? height,
  double? width,
}) =>
    Node(
      type: MapBlockKeys.type,
      attributes: {
        MapBlockKeys.viewId: viewId,
        if (latitude != null) MapBlockKeys.latitude: latitude,
        if (longitude != null) MapBlockKeys.longitude: longitude,
        if (zoom != null) MapBlockKeys.zoom: zoom,
        if (place.isNotEmpty) MapBlockKeys.place: place,
        if (height != null) MapBlockKeys.height: height,
        if (width != null) MapBlockKeys.width: width,
      },
    );

/// A map placed in a page.
///
/// It is a live map, not a picture of one and not a link: it pans, zooms and
/// answers its markers. Point it at a table and it follows the rows.
class MapBlockComponentBuilder extends BlockComponentBuilder {
  MapBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MapBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => true;
}

class MapBlockComponent extends BlockComponentStatefulWidget {
  const MapBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MapBlockComponent> createState() => _MapBlockComponentState();
}

class _MapBlockComponentState extends State<MapBlockComponent>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  static const double _minimumHeight = 220;
  static const double _defaultHeight = 340;
  static const double _minimumWidth = 320;
  static const double _defaultWidth = 720;

  final PopoverController _picker = PopoverController();
  final AppMapController _map = AppMapController();

  /// Waiting for a click on the map to say where the pin goes.
  bool _picking = false;

  @override
  void dispose() {
    _picker.close();
    _map.dispose();
    super.dispose();
  }

  String get _viewId => node.attributes[MapBlockKeys.viewId] as String? ?? '';

  String get _place => node.attributes[MapBlockKeys.place] as String? ?? '';

  LatLng? get _pinned =>
      _pointAt(MapBlockKeys.latitude, MapBlockKeys.longitude);

  LatLng? get _viewCenter =>
      _pointAt(MapBlockKeys.viewLatitude, MapBlockKeys.viewLongitude);

  LatLng? _pointAt(String latitudeKey, String longitudeKey) {
    final lat = node.attributes[latitudeKey];
    final lng = node.attributes[longitudeKey];
    if (lat is! num || lng is! num) {
      return null;
    }
    return LatLng.clamped(lat.toDouble(), lng.toDouble());
  }

  double? get _zoom {
    final stored = node.attributes[MapBlockKeys.zoom];
    return stored is num ? stored.toDouble() : null;
  }

  double get _height {
    final stored = node.attributes[MapBlockKeys.height];
    return stored is num ? stored.toDouble() : _defaultHeight;
  }

  double get _width {
    final stored = node.attributes[MapBlockKeys.width];
    return stored is num ? stored.toDouble() : _defaultWidth;
  }

  MapSpec get _spec {
    final stored = node.attributes[MapBlockKeys.spec];
    return MapSpec.fromJson(
      stored is Map ? Map<String, dynamic>.from(stored) : const {},
    );
  }

  EditorState get _editorState => context.read<EditorState>();

  bool get _editable => _editorState.editable;

  bool get _isConfigured => _viewId.isNotEmpty || _pinned != null;

  Future<void> _update(
    Map<String, Object?> attributes, {
    bool recordUndo = true,
  }) {
    final transaction = _editorState.transaction
      ..updateNode(node, {...node.attributes, ...attributes});
    return _editorState.apply(
      transaction,
      options: ApplyOptions(recordUndo: recordUndo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = mapPaletteOf(context);

    Widget child = ResizableMedia(
      width: _width,
      minWidth: _minimumWidth,
      height: _height,
      minHeight: _minimumHeight,
      maxHeight: 900,
      alignment: blockEmbedAlignment(node),
      editable: _editable,
      onResize: (value) => _update({MapBlockKeys.width: value}),
      onResizeHeight: (value) => _update({MapBlockKeys.height: value}),
      child: _isConfigured || (_picking && _editable)
          ? _buildMap(palette)
          : _MapEmptyFrame(
              palette: palette,
              onPickTable: _picker.show,
              onPlaceFound: (point, label) =>
                  _pinPlace(point, label, frame: true),
              onChooseOnMap:
                  _editable ? () => setState(() => _picking = true) : null,
            ),
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }

    return AppFlowyPopover(
      controller: _picker,
      triggerActions: PopoverTriggerFlags.none,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 400,
        maxWidth: 400,
        maxHeight: 330,
      ),
      animationDuration: const Duration(milliseconds: 140),
      beginScaleFactor: 0.98,
      asBarrier: true,
      popupBuilder: (_) => WorkspaceViewPickerMenu(
        contentKey: const ValueKey('map-table-picker-menu'),
        title: LocaleKeys.map_useLocationsFrom.tr(),
        searchHint: LocaleKeys.search_label.tr(),
        emptyMessage: LocaleKeys.charts_noTables.tr(),
        errorMessage: LocaleKeys.document_mobilePageSelector_failedToLoad.tr(),
        selectedViewId: _viewId.isEmpty ? null : _viewId,
        viewFilter: isDatabaseTable,
        leadingBuilder: (context, view, palette) => WorkspaceItemIcon.fromView(
          view: view,
          size: 17,
          color: palette.textSecondary,
        ),
        onSelected: _selectTable,
      ),
      child: child,
    );
  }

  Widget _buildMap(MapPalette palette) {
    // The editor owns the wheel everywhere else on the page; a map has to take
    // it back or panning the page would zoom the map and the reverse.
    final body = PremiumScrollExclusion(
      child: _viewId.isNotEmpty ? _linkedMap() : _placeMap(palette),
    );
    return ViewerCard(reactsToPointer: false, child: body);
  }

  Widget _linkedMap() => MapStage(
        key: ValueKey(_viewId),
        viewId: _viewId,
        spec: _spec,
        framed: false,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        title: _place.isEmpty ? null : _place,
        onSpecChanged: (spec) => _update({MapBlockKeys.spec: spec.toJson()}),
        trailing: _pickButton(),
      );

  /// The map of one place — or, while a place is being chosen on it, of none
  /// yet. Both are the same map, so the view survives the pin landing.
  Widget _placeMap(MapPalette palette) {
    final point = _pinned;
    final picking = _picking && _editable;
    final title = point == null
        ? ''
        : _place.isEmpty
            ? point.label
            : _place;
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MouseRegion(
              // A crosshair says the next click lands the pin.
              cursor: picking ? SystemMouseCursors.precise : MouseCursor.defer,
              child: AppMapView(
                controller: _map,
                pins: [
                  if (point != null)
                    AppMapPin(
                      id: 'pinned',
                      point: point,
                      title: title,
                      subtitle: point.label,
                    ),
                ],
                initialCenter: _viewCenter ?? point,
                initialZoom: _zoom ?? (point == null ? null : 14),
                autoFit: false,
                clustering: false,
                showSearch: true,
                searchHint: LocaleKeys.map_searchHint.tr(),
                onSearch: _lookUp,
                onSuggestionPicked: _editable ? _pinSuggestion : null,
                onViewportChanged: _rememberView,
                onPointTap: picking ? _pinPoint : null,
                onContextMenu: _showContextMenu,
                padding: const EdgeInsets.only(top: 34),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 10,
          child: _Header(
            palette: palette,
            title: picking ? LocaleKeys.map_pinFromMap.tr() : title,
            picking: picking,
            onTogglePick:
                _editable ? () => setState(() => _picking = !_picking) : null,
            onRemovePin:
                _editable && point != null && !picking ? _removePin : null,
          ),
        ),
      ],
    );
  }

  Widget _pickButton() => IconButton(
        onPressed: _picker.show,
        icon: const Icon(Icons.table_chart_rounded, size: 16),
        tooltip: LocaleKeys.map_useLocationsFrom.tr(),
        visualDensity: VisualDensity.compact,
      );

  Future<void> _showContextMenu(Offset globalPosition, LatLng point) async {
    await showAppMenu<void>(
      context: context,
      anchor: globalPosition & Size.zero,
      entries: [
        if (_editable) ...[
          AppMenuItem(
            label: LocaleKeys.map_pinHere.tr(),
            icon: Icons.add_location_alt_rounded,
            onSelected: () => _pinPoint(point),
          ),
          if (_pinned != null)
            AppMenuItem(
              label: LocaleKeys.map_removePin.tr(),
              icon: Icons.location_off_rounded,
              destructive: true,
              onSelected: _removePin,
            ),
          const AppMenuSeparator(),
        ],
        AppMenuItem(
          label: LocaleKeys.map_copyCoordinates.tr(),
          icon: Icons.copy_rounded,
          onSelected: () => copyMapCoordinates(context, point),
        ),
        AppMenuItem(
          label: LocaleKeys.map_openInGoogleMaps.tr(),
          icon: Icons.open_in_new_rounded,
          onSelected: () => openInGoogleMaps(point),
        ),
      ],
    );
  }

  void _rememberView(MapViewport viewport) {
    if (!mounted || !_editable) {
      return;
    }
    // Looking around is worth keeping, but not worth undoing one pan at a
    // time.
    unawaited(
      _update(
        {
          MapBlockKeys.viewLatitude: viewport.center.latitude,
          MapBlockKeys.viewLongitude: viewport.center.longitude,
          MapBlockKeys.zoom: viewport.zoom,
        },
        recordUndo: false,
      ),
    );
  }

  void _pinPoint(LatLng point) {
    if (!mounted) {
      return;
    }
    setState(() => _picking = false);
    unawaited(_pinPlace(point, point.label));
  }

  /// Takes the pin away, and with it where the map was looking: the block goes
  /// back to asking for a place.
  void _removePin() {
    if (!mounted || !_editable) {
      return;
    }
    setState(() => _picking = false);
    unawaited(
      _update({
        MapBlockKeys.latitude: null,
        MapBlockKeys.longitude: null,
        MapBlockKeys.place: null,
        MapBlockKeys.viewLatitude: null,
        MapBlockKeys.viewLongitude: null,
        MapBlockKeys.zoom: null,
      }),
    );
  }

  void _pinSuggestion(MapSuggestion suggestion) {
    if (!mounted) {
      return;
    }
    setState(() => _picking = false);
    unawaited(_pinPlace(suggestion.point, suggestion.title));
  }

  Future<LatLng?> _lookUp(String query) async {
    final parsed = parseMapLocation(query);
    if (parsed.point != null) {
      _pinSuggestion(MapSuggestion(title: parsed.label, point: parsed.point!));
      return parsed.point;
    }
    final geocoder = resolveGeocoder(apiKey: MapsSettings.instance.apiKey);
    final found = await geocoder.search(query, limit: 1);
    if (found.isEmpty) {
      return null;
    }
    _pinSuggestion(
      MapSuggestion(
        title:
            found.first.name.isEmpty ? found.first.address : found.first.name,
        point: found.first.point,
      ),
    );
    return found.first.point;
  }

  /// Puts the pin on [point]. [frame] also leaves the map looking at it, for a
  /// place chosen before there was a map to look with.
  Future<void> _pinPlace(LatLng point, String label, {bool frame = false}) {
    if (!_editable) {
      return Future.value();
    }
    return _update({
      MapBlockKeys.latitude: point.latitude,
      MapBlockKeys.longitude: point.longitude,
      MapBlockKeys.place: label,
      if (frame) ...{
        MapBlockKeys.viewLatitude: point.latitude,
        MapBlockKeys.viewLongitude: point.longitude,
        MapBlockKeys.zoom: 14.0,
      },
    });
  }

  Future<void> _selectTable(ViewPB picked) async {
    _picker.close();
    await _update({
      MapBlockKeys.viewId: picked.id,
      MapBlockKeys.place: picked.name,
      // A different table means different columns, so the reading starts over.
      MapBlockKeys.spec: const MapSpec().toJson(),
    });
  }
}

/// The floating strip over a pinned map.
class _Header extends StatelessWidget {
  const _Header({
    required this.palette,
    required this.title,
    required this.picking,
    this.onTogglePick,
    this.onRemovePin,
  });

  final MapPalette palette;
  final String title;

  /// Waiting for a click on the map: the strip says so and offers a way out.
  final bool picking;
  final VoidCallback? onTogglePick;
  final VoidCallback? onRemovePin;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: title.isEmpty ? const SizedBox.shrink() : _chip(),
          ),
        ),
        if (onTogglePick != null) ...[
          const SizedBox(width: 8),
          MapControlGroup(
            palette: palette,
            axis: Axis.horizontal,
            children: [
              MapControlButton(
                key: const ValueKey('map-block-pick-toggle'),
                icon: picking
                    ? Icons.close_rounded
                    : Icons.add_location_alt_rounded,
                tooltip: picking
                    ? LocaleKeys.button_cancel.tr()
                    : LocaleKeys.map_movePin.tr(),
                palette: palette,
                selected: picking,
                size: 26,
                onPressed: onTogglePick,
              ),
              if (onRemovePin != null)
                MapControlButton(
                  key: const ValueKey('map-block-remove-pin'),
                  icon: Icons.location_off_rounded,
                  tooltip: LocaleKeys.map_removePin.tr(),
                  palette: palette,
                  size: 26,
                  onPressed: onRemovePin,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.floating.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(MapMetrics.controlRadius),
        boxShadow: palette.chromeShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            picking ? Icons.ads_click_rounded : Icons.place_rounded,
            size: 14,
            color: palette.accent,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.2,
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
                fontVariations: flowyFontVariationsForWeight(FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the block shows before it has been pointed anywhere.
class _MapEmptyFrame extends StatefulWidget {
  const _MapEmptyFrame({
    required this.palette,
    required this.onPickTable,
    required this.onPlaceFound,
    this.onChooseOnMap,
  });

  final MapPalette palette;
  final VoidCallback onPickTable;
  final Future<void> Function(LatLng point, String label) onPlaceFound;

  /// Opens the map itself to click a place on, rather than typing one.
  final VoidCallback? onChooseOnMap;

  @override
  State<_MapEmptyFrame> createState() => _MapEmptyFrameState();
}

class _MapEmptyFrameState extends State<_MapEmptyFrame> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  bool _notFound = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _notFound = false;
    });
    try {
      final parsed = parseMapLocation(query);
      if (parsed.point != null) {
        await widget.onPlaceFound(parsed.point!, parsed.label);
        return;
      }
      final geocoder = resolveGeocoder(apiKey: MapsSettings.instance.apiKey);
      final found = await geocoder.search(query, limit: 1);
      if (found.isEmpty) {
        setState(() => _notFound = true);
        return;
      }
      await widget.onPlaceFound(found.first.point, found.first.name);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: palette.chromeShadow,
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.map_rounded,
                  size: 26,
                  color: palette.textMuted,
                ),
                const SizedBox(height: 11),
                Text(
                  LocaleKeys.map_blockPlaceholder.tr(),
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.25,
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontVariations:
                        flowyFontVariationsForWeight(FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _notFound
                      ? LocaleKeys.map_nothingToPlace.tr()
                      : LocaleKeys.map_blockHint.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 360,
                  child: Row(
                    children: [
                      Expanded(
                        child: MapPlaceField(
                          key: const ValueKey('map-block-place-field'),
                          palette: palette,
                          controller: _controller,
                          hintText: LocaleKeys.map_locationCellHint.tr(),
                          onPicked: (suggestion) => unawaited(
                            widget.onPlaceFound(
                              suggestion.point,
                              suggestion.title,
                            ),
                          ),
                          onSubmitted: (_) => _find(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 34,
                        child: FilledButton(
                          onPressed: _busy ? null : _find,
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.7,
                                  ),
                                )
                              : Text(LocaleKeys.map_pinHere.tr()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    if (widget.onChooseOnMap != null)
                      TextButton.icon(
                        key: const ValueKey('map-block-choose-on-map'),
                        onPressed: widget.onChooseOnMap,
                        icon: const Icon(
                          Icons.add_location_alt_rounded,
                          size: 15,
                        ),
                        label: Text(LocaleKeys.map_chooseOnMap.tr()),
                      ),
                    TextButton.icon(
                      onPressed: widget.onPickTable,
                      icon: const Icon(Icons.table_chart_rounded, size: 15),
                      label: Text(LocaleKeys.map_useLocationsFrom.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
