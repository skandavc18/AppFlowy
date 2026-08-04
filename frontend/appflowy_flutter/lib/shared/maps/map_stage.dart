import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/maps/app_map_toolbar.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/maps/map_source.dart';
import 'package:appflowy/workspace/application/maps/map_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// A map of a table, with the chrome every other viewer in the application
/// wears: a quiet header, a floating toolbar, and no borders.
class MapStage extends StatefulWidget {
  const MapStage({
    super.key,
    required this.viewId,
    required this.spec,
    required this.onSpecChanged,
    this.title,
    this.onOpenRow,
    this.onAddRow,
    this.padding = EdgeInsets.zero,
    this.framed = true,
    this.showHeader = true,
    this.trailing,
    this.height,
  });

  final String viewId;
  final MapSpec spec;
  final ValueChanged<MapSpec> onSpecChanged;
  final String? title;

  /// Opening a marker's row, when the host can do that.
  final ValueChanged<String>? onOpenRow;

  /// Adding a row for a place, when the host can do that.
  final Future<void> Function(LatLng point)? onAddRow;

  final EdgeInsets padding;
  final bool framed;
  final bool showHeader;
  final Widget? trailing;
  final double? height;

  @override
  State<MapStage> createState() => MapStageState();
}

class MapStageState extends State<MapStage> {
  /// Where a row lands when it is added without a place being clicked.
  static const _defaultPlace = LatLng(0, 0);

  late MapSource _source = MapSource(
    viewId: widget.viewId,
    apiKey: MapsSettings.instance.apiKey,
  );
  final AppMapController _map = AppMapController();

  String _search = '';
  Set<String>? _matches;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _source
      ..updateSpec(widget.spec)
      ..addListener(_onSourceChanged);
    unawaited(_source.load());
  }

  @override
  void didUpdateWidget(MapStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId) {
      _source.removeListener(_onSourceChanged);
      _source.dispose();
      _source = MapSource(
        viewId: widget.viewId,
        apiKey: MapsSettings.instance.apiKey,
      )
        ..updateSpec(widget.spec)
        ..addListener(_onSourceChanged);
      unawaited(_source.load());
    } else if (oldWidget.spec != widget.spec) {
      _source.updateSpec(widget.spec);
    }
  }

  @override
  void dispose() {
    _viewportTimer?.cancel();
    _source.removeListener(_onSourceChanged);
    _source.dispose();
    _map.dispose();
    super.dispose();
  }

  /// Waits for the pan or zoom to finish before writing where the map was left.
  ///
  /// Every frame of a drag moves the camera, and every one of those used to
  /// reach the folder as a saved view.
  Timer? _viewportTimer;

  void _rememberViewport(MapViewport viewport) {
    _viewportTimer?.cancel();
    _viewportTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) {
        return;
      }
      final spec = widget.spec;
      if (spec.center == viewport.center && spec.zoom == viewport.zoom) {
        return;
      }
      widget.onSpecChanged(
        spec.copyWith(center: viewport.center, zoom: viewport.zoom),
      );
    });
  }

  void _onSourceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Reads the table again — the host calls this when a row changes.
  void reload() => _source.invalidate();

  void _highlight(String query) {
    final trimmed = query.trim().toLowerCase();
    setState(() {
      _search = trimmed;
      _matches = trimmed.isEmpty
          ? null
          : _source.pins
              .where(
                (pin) =>
                    pin.title.toLowerCase().contains(trimmed) ||
                    pin.subtitle.toLowerCase().contains(trimmed),
              )
              .map((pin) => pin.id)
              .toSet();
    });
  }

  /// Rows already on the map whose name matches what is being typed.
  List<MapSuggestion> _suggestPins(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return const [];
    }
    return _source.pins
        .where(
          (pin) =>
              pin.title.toLowerCase().contains(trimmed) ||
              pin.subtitle.toLowerCase().contains(trimmed),
        )
        .take(4)
        .map(
          (pin) => MapSuggestion(
            title: pin.title,
            subtitle: pin.subtitle,
            point: pin.point,
            pinId: pin.id,
          ),
        )
        .toList();
  }

  Future<LatLng?> _searchPlace(String query) async {
    _highlight(query);
    final matched = _matches;
    if (matched != null && matched.isNotEmpty) {
      final pin = _source.pins
          .firstWhere((candidate) => matched.contains(candidate.id));
      return pin.point;
    }
    // Nothing on the map matches, so look the words up as a place instead.
    final geocoder = resolveGeocoder(apiKey: MapsSettings.instance.apiKey);
    final found = await geocoder.search(query, limit: 1);
    return found.isEmpty ? null : found.first.point;
  }

  @override
  Widget build(BuildContext context) {
    final palette = mapPaletteOf(context);
    final map = _buildMap(palette);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showHeader) _buildHeader(palette),
        if (widget.showHeader) const SizedBox(height: 10),
        Expanded(child: map),
      ],
    );

    final sized = SizedBox(
      height: widget.height,
      child: Padding(padding: widget.padding, child: body),
    );

    if (!widget.framed) {
      return sized;
    }
    // The card must paint a surface: a transparent one lets its own shadow
    // blur across its whole face, which reads as a grey halo round the map.
    return ViewerCard(
      reactsToPointer: false,
      color: palette.surface,
      child: sized,
    );
  }

  Widget _buildMap(MapPalette palette) {
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(widget.framed ? 12 : 0),
      child: AppMapView(
        controller: _map,
        pins: _source.pins,
        provider: widget.spec.provider,
        apiKey: MapsSettings.instance.apiKey,
        style: widget.spec.style,
        clustering: widget.spec.clustering,
        initialCenter: widget.spec.center,
        initialZoom: widget.spec.zoom,
        highlightedPinIds: _matches,
        showSearch: true,
        searchHint: LocaleKeys.map_searchHint.tr(),
        onSearch: _searchPlace,
        onSuggestPins: _suggestPins,
        emptyHint: _emptyHint(),
        onEmptyHintTap: _onHintTap(),
        onPinTap: widget.onOpenRow == null
            ? null
            : (pin) => widget.onOpenRow!(pin.id),
        onFullscreen: () => setState(() => _fullscreen = !_fullscreen),
        isFullscreen: _fullscreen,
        onViewportChanged: _rememberViewport,
        onContextMenu: _showContextMenu,
      ),
    );

    if (!_fullscreen) {
      return clipped;
    }
    return clipped;
  }

  String _emptyHint() {
    if (_source.isLoading) {
      return LocaleKeys.map_loading.tr();
    }
    final error = _source.error;
    if (error != null && error.isNotEmpty) {
      return error;
    }
    if (!_source.spec.isConfigured) {
      return LocaleKeys.map_pickLocationColumn.tr();
    }
    if (_source.columnMissing) {
      return LocaleKeys.map_columnMissing.tr();
    }
    if (_source.filled == 0) {
      final name = _source.locationColumnName;
      return name.isEmpty
          ? LocaleKeys.map_nothingToPlace.tr()
          : LocaleKeys.map_columnEmpty.tr(namedArgs: {'name': name});
    }
    if (_source.pendingLookups > 0) {
      return LocaleKeys.map_lookingUp
          .tr(namedArgs: {'count': '${_source.pendingLookups}'});
    }
    if (_source.unplaced > 0) {
      return LocaleKeys.map_couldNotPlace
          .tr(namedArgs: {'count': '${_source.unplaced}'});
    }
    return LocaleKeys.map_nothingToPlace.tr();
  }

  /// What the hint should do when it is tapped, if anything.
  VoidCallback? _onHintTap() {
    if (_source.error?.isNotEmpty ?? false) {
      return reload;
    }
    if (!_source.spec.isConfigured || _source.columnMissing) {
      return _pickLocationColumn;
    }
    if (_source.filled == 0 && widget.onAddRow != null) {
      return () => unawaited(
            _addRow(widget.onAddRow!, _map.camera?.center ?? _defaultPlace),
          );
    }
    return _source.unplaced > 0 ? reload : null;
  }

  Future<void> _showContextMenu(Offset globalPosition, LatLng point) async {
    final addRow = widget.onAddRow;
    await showAppMenu<void>(
      context: context,
      anchor: globalPosition & Size.zero,
      entries: [
        if (addRow != null) ...[
          AppMenuItem(
            label: LocaleKeys.map_addRowHere.tr(),
            icon: Icons.add_location_alt_rounded,
            onSelected: () => unawaited(_addRow(addRow, point)),
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
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.map_resetView.tr(),
          icon: Icons.explore_rounded,
          onSelected: _map.resetView,
        ),
      ],
    );
  }

  /// Adds a row and reads the table again so its pin appears at once.
  Future<void> _addRow(
    Future<void> Function(LatLng) add,
    LatLng point,
  ) async {
    await add(point);
    reload();
  }

  /// The way out of "choose the column that holds a place".
  Future<void> _pickLocationColumn() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    await showAppMenu<void>(
      context: context,
      anchor: box.localToGlobal(box.size.center(Offset.zero)) & Size.zero,
      entries: [
        AppMenuHeader(LocaleKeys.map_locationColumn.tr()),
        ..._locationColumnEntries(),
      ],
    );
  }

  List<AppMenuEntry> _locationColumnEntries() {
    final spec = widget.spec;
    final fields = _source.locationCandidates;
    if (fields.isEmpty) {
      return [
        AppMenuItem(
          label: LocaleKeys.map_noLocationColumns.tr(),
          enabled: false,
        ),
      ];
    }
    return [
      for (final field in fields)
        AppMenuItem(
          label: field.name,
          icon: Icons.place_rounded,
          selected: spec.locationColumns.contains(field.id),
          onSelected: () => widget.onSpecChanged(
            spec.copyWith(locationColumns: [field.id]),
          ),
        ),
    ];
  }

  // ------------------------------------------------------------------ header

  Widget _buildHeader(MapPalette palette) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              if (widget.title != null && widget.title!.isNotEmpty) ...[
                Flexible(
                  child: Text(
                    widget.title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.2,
                      letterSpacing: -0.2,
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontVariations:
                          flowyFontVariationsForWeight(FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              _MapMeta(source: _source, palette: palette, search: _search),
            ],
          ),
        ),
        if (widget.trailing != null) widget.trailing!,
        if (widget.onAddRow != null)
          MapControlButton(
            icon: Icons.add_location_alt_rounded,
            tooltip: LocaleKeys.map_addRowHere.tr(),
            palette: palette,
            size: 28,
            onPressed: () => unawaited(
              _addRow(widget.onAddRow!, _map.camera?.center ?? _defaultPlace),
            ),
          ),
        _MapMenuButton(
          palette: palette,
          entries: _menuEntries,
        ),
      ],
    );
  }

  List<AppMenuEntry> _menuEntries() {
    final spec = widget.spec;
    final allFields = _source.fields;

    return [
      AppMenuHeader(LocaleKeys.map_locationColumn.tr()),
      ..._locationColumnEntries(),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.map_colorBy.tr(),
        icon: Icons.palette_rounded,
        submenu: [
          AppMenuItem(
            label: LocaleKeys.map_none.tr(),
            selected: spec.colorColumn.isEmpty,
            onSelected: () =>
                widget.onSpecChanged(spec.copyWith(colorColumn: '')),
          ),
          for (final field in allFields.where(_canColour))
            AppMenuItem(
              label: field.name,
              selected: spec.colorColumn == field.id,
              onSelected: () =>
                  widget.onSpecChanged(spec.copyWith(colorColumn: field.id)),
            ),
        ],
      ),
      AppMenuItem(
        label: LocaleKeys.map_style.tr(),
        icon: Icons.layers_rounded,
        submenu: [
          AppMenuItem(
            label: LocaleKeys.map_styleAuto.tr(),
            selected: spec.style == null,
            onSelected: () =>
                widget.onSpecChanged(spec.copyWith(clearStyle: true)),
          ),
          for (final style in MapStyleName.values)
            AppMenuItem(
              label: mapStyleLabel(style),
              selected: spec.style == style,
              onSelected: () =>
                  widget.onSpecChanged(spec.copyWith(style: style)),
            ),
        ],
      ),
      AppMenuItem(
        label: LocaleKeys.map_clusterNearby.tr(),
        icon: Icons.workspaces_rounded,
        selected: spec.clustering,
        onSelected: () =>
            widget.onSpecChanged(spec.copyWith(clustering: !spec.clustering)),
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.map_refresh.tr(),
        icon: Icons.refresh_rounded,
        onSelected: reload,
      ),
    ];
  }

  static bool _canColour(FieldPB field) => const [
        FieldType.SingleSelect,
        FieldType.MultiSelect,
        FieldType.Checkbox,
        FieldType.RichText,
      ].contains(field.fieldType);
}

/// What the map is showing, in a line.
class _MapMeta extends StatelessWidget {
  const _MapMeta({
    required this.source,
    required this.palette,
    required this.search,
  });

  final MapSource source;
  final MapPalette palette;
  final String search;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      LocaleKeys.map_placeCount
          .tr(namedArgs: {'count': '${source.pins.length}'}),
      if (source.pendingLookups > 0)
        LocaleKeys.map_lookingUp
            .tr(namedArgs: {'count': '${source.pendingLookups}'}),
    ];
    return Text(
      parts.join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.2,
        color: palette.textMuted,
      ),
    );
  }
}

class _MapMenuButton extends StatelessWidget {
  const _MapMenuButton({required this.palette, required this.entries});

  final MapPalette palette;
  final List<AppMenuEntry> Function() entries;

  @override
  Widget build(BuildContext context) => AppMenuIconButton(
        icon: Icons.more_horiz_rounded,
        tooltip: LocaleKeys.map_options.tr(),
        iconColor: palette.textMuted,
        width: 236,
        entries: entries,
      );
}

/// What a basemap is called.
String mapStyleLabel(MapStyleName style) => switch (style) {
      MapStyleName.streets => LocaleKeys.map_styleStreets.tr(),
      MapStyleName.light => LocaleKeys.map_styleLight.tr(),
      MapStyleName.dark => LocaleKeys.map_styleDark.tr(),
      MapStyleName.paper => LocaleKeys.map_stylePaper.tr(),
      MapStyleName.satellite => LocaleKeys.map_styleSatellite.tr(),
    };

/// Puts a point on the clipboard the way every map writes them.
void copyMapCoordinates(BuildContext context, LatLng point) {
  Clipboard.setData(ClipboardData(text: point.label));
}

/// Hands a point to Google Maps in the browser.
Future<void> openInGoogleMaps(LatLng point) async {
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': '${point.latitude},${point.longitude}',
  });
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
