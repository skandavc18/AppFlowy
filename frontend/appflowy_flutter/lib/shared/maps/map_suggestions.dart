import 'dart:async';

import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:flutter/material.dart';

/// A place offered while someone is still typing.
@immutable
class MapSuggestion {
  const MapSuggestion({
    required this.title,
    required this.point,
    this.subtitle = '',
    this.pinId,
  });

  final String title;
  final String subtitle;
  final LatLng point;

  /// Set when the suggestion is a row already on the map.
  final String? pinId;

  bool get isPin => pinId != null;

  /// What to write into a cell or a search box when this is chosen.
  String get value => subtitle.isEmpty ? title : subtitle;
}

/// Looks up half-typed places, and remembers what it found.
///
/// Nominatim allows one call a second, so the same few letters must never be
/// asked twice and a burst of keystrokes must collapse into one question.
class MapSuggestionCache {
  MapSuggestionCache._();

  static final MapSuggestionCache instance = MapSuggestionCache._();

  final Map<String, List<MapSuggestion>> _found = {};
  final Map<String, Future<List<MapSuggestion>>> _asking = {};

  Future<List<MapSuggestion>> search(String query, {int limit = 5}) {
    final key = query.trim().toLowerCase();
    if (key.length < 3) {
      return Future.value(const []);
    }
    final cached = _found[key];
    if (cached != null) {
      return Future.value(cached);
    }
    return _asking.putIfAbsent(key, () async {
      try {
        final geocoder = resolveGeocoder(apiKey: MapsSettings.instance.apiKey);
        final results = await geocoder.search(query, limit: limit);
        final suggestions = results
            .map(
              (result) => MapSuggestion(
                title: result.name.isEmpty ? result.address : result.name,
                subtitle: result.address,
                point: result.point,
              ),
            )
            .toList();
        if (_found.length > 200) {
          _found.clear();
        }
        _found[key] = suggestions;
        return suggestions;
      } on Object {
        return const <MapSuggestion>[];
      } finally {
        _asking.removeWhere((asked, _) => asked == key);
      }
    });
  }
}

/// Everything worth offering for [query]: a typed coordinate pair first, then
/// places found by name.
Future<List<MapSuggestion>> suggestPlaces(String query, {int limit = 5}) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const [];
  }
  final suggestions = <MapSuggestion>[];
  final typed = parseMapLocation(trimmed).point;
  if (typed != null) {
    suggestions.add(MapSuggestion(title: typed.label, point: typed));
  }
  suggestions.addAll(await MapSuggestionCache.instance.search(trimmed));
  return suggestions.take(limit + 1).toList();
}

/// The card of places that drops out of a search box or a cell.
class MapSuggestionList extends StatelessWidget {
  const MapSuggestionList({
    super.key,
    required this.palette,
    required this.suggestions,
    required this.onPicked,
    this.width = MapMetrics.searchWidth,
    this.maxHeight = 264,
    this.framed = true,
    this.hint = '',
    this.busy = false,
    this.freeText = '',
    this.onFreeText,
  });

  final MapPalette palette;
  final List<MapSuggestion> suggestions;
  final ValueChanged<MapSuggestion> onPicked;
  final double width;
  final double maxHeight;

  /// Whether to draw its own card, or sit inside somebody else's.
  final bool framed;

  /// Shown while there is nothing to offer yet.
  final String hint;
  final bool busy;

  /// Keeping whatever was typed, when it is not a place anybody can find.
  final String freeText;
  final ValueChanged<String>? onFreeText;

  bool get _alreadyOffered => suggestions.any(
        (suggestion) =>
            suggestion.value.toLowerCase() == freeText.toLowerCase(),
      );

  @override
  Widget build(BuildContext context) {
    final keepTyped =
        onFreeText != null && freeText.isNotEmpty && !_alreadyOffered;
    if (suggestions.isEmpty && hint.isEmpty && !keepTyped) {
      return const SizedBox.shrink();
    }
    return Container(
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: framed
          ? BoxDecoration(
              color: palette.floating,
              borderRadius:
                  BorderRadius.circular(MapMetrics.controlGroupRadius),
              border: Border.all(
                color: palette.border.withValues(alpha: 0.5),
                width: 0.8,
              ),
              boxShadow: palette.popupShadow,
            )
          : null,
      clipBehavior: framed ? Clip.antiAlias : Clip.none,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (keepTyped)
              _Row(
                palette: palette,
                icon: Icons.edit_location_alt_rounded,
                title: freeText,
                subtitle: '',
                onPicked: () => onFreeText!(freeText),
              ),
            for (final suggestion in suggestions)
              _Row(
                palette: palette,
                icon: suggestion.isPin
                    ? Icons.push_pin_rounded
                    : Icons.place_rounded,
                accent: suggestion.isPin,
                title: suggestion.title,
                subtitle: suggestion.subtitle == suggestion.title
                    ? ''
                    : suggestion.subtitle,
                onPicked: () => onPicked(suggestion),
              ),
            if (suggestions.isEmpty && hint.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    if (busy) ...[
                      SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPicked,
    this.accent = false,
  });

  final MapPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPicked;
  final bool accent;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // A pointer down applies the place before the text field can lose
      // focus, which is what would otherwise close the cell mid-tap.
      child: Listener(
        onPointerDown: (_) => widget.onPicked(),
        child: AnimatedContainer(
          duration: MapMetrics.hover,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          color: _hovered ? palette.hover : palette.hover.withValues(alpha: 0),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 15,
                color: widget.accent ? palette.accent : palette.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.25,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty)
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Watches a text field and offers places under it.
///
/// Owning the debounce and the stale-answer guard here means a search box and
/// a table cell behave the same without either of them knowing about
/// geocoding.
class MapSuggestionBox extends StatefulWidget {
  const MapSuggestionBox({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.builder,
    this.enabled = true,
    this.openOnFocus = false,
    this.extra,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final MapSuggestionBoxBuilder builder;
  final bool enabled;

  /// Opens the list the moment the field is entered, before a word is typed.
  final bool openOnFocus;

  /// Matches the host already knows about, offered above the looked-up ones.
  final List<MapSuggestion> Function(String query)? extra;

  @override
  State<MapSuggestionBox> createState() => _MapSuggestionBoxState();
}

/// What the box has to offer right now.
@immutable
class MapSuggestionStatus {
  const MapSuggestionStatus({
    required this.suggestions,
    required this.open,
    required this.busy,
  });

  final List<MapSuggestion> suggestions;

  /// Whether a host should be showing anything at all.
  final bool open;
  final bool busy;
}

typedef MapSuggestionBoxBuilder = Widget Function(
  BuildContext context,
  MapSuggestionStatus status,
);

class _MapSuggestionBoxState extends State<MapSuggestionBox> {
  List<MapSuggestion> _suggestions = const [];
  Timer? _debounce;
  int _generation = 0;
  String _asked = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTyped);
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(MapSuggestionBox old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onTyped);
      widget.controller.addListener(_onTyped);
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    if (old.enabled && !widget.enabled) {
      _clear();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTyped);
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      _onTyped();
      if (mounted) {
        setState(() {});
      }
      return;
    }
    _clear();
  }

  void _clear() {
    _debounce?.cancel();
    _generation++;
    _asked = '';
    if (mounted) {
      setState(() {
        _suggestions = const [];
        _busy = false;
      });
    }
  }

  void _onTyped() {
    if (!widget.enabled || !widget.focusNode.hasFocus) {
      return;
    }
    final query = widget.controller.text.trim();
    if (query == _asked) {
      return;
    }
    _asked = query;
    _debounce?.cancel();
    if (query.length < 3) {
      setState(() {
        _suggestions = const [];
        _busy = false;
      });
      return;
    }
    final local = widget.extra?.call(query) ?? const <MapSuggestion>[];
    setState(() {
      _suggestions = local;
      _busy = true;
    });
    _debounce = Timer(const Duration(milliseconds: 320), () => _look(query));
  }

  Future<void> _look(String query) async {
    final generation = ++_generation;
    final found = await suggestPlaces(query);
    if (!mounted || generation != _generation) {
      return;
    }
    final local = widget.extra?.call(query) ?? const <MapSuggestion>[];
    setState(() {
      _suggestions = [...local, ...found];
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        MapSuggestionStatus(
          suggestions: widget.enabled ? _suggestions : const [],
          open: widget.enabled &&
              (_suggestions.isNotEmpty ||
                  (widget.openOnFocus && widget.focusNode.hasFocus)),
          busy: _busy,
        ),
      );
}
