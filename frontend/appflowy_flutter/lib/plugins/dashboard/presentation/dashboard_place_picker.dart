import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A place that has been chosen, with the coordinates already looked up.
@immutable
class DashboardPlace {
  const DashboardPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;
}

/// Search for a place and pick one.
///
/// Free text is not enough: a name has to be turned into coordinates before
/// anything can be read for it, and doing that silently in the background is
/// how "I typed a town and nothing happened" happens. Here the look-up IS the
/// picker, so what was chosen is unambiguous.
Future<DashboardPlace?> showDashboardPlacePicker({
  required BuildContext context,
  required DashboardPalette palette,
  String initialQuery = '',
}) =>
    showDialog<DashboardPlace>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: palette.isDark ? 0.5 : 0.22),
      builder: (_) =>
          _PlacePicker(palette: palette, initialQuery: initialQuery),
    );

class _PlacePicker extends StatefulWidget {
  const _PlacePicker({required this.palette, required this.initialQuery});

  final DashboardPalette palette;
  final String initialQuery;

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  late final TextEditingController _query =
      TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<GeocodeResult> _results = const [];
  bool _searching = false;
  String? _failure;

  /// Answers can arrive out of order; only the newest one is adopted.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().length >= 2) {
      unawaited(_search(widget.initialQuery));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _schedule(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _results = const [];
        _failure = null;
      });
      return;
    }
    // The geocoder allows one call a second, so a keystroke is not a request.
    _debounce = Timer(
      const Duration(milliseconds: 420),
      () => unawaited(_search(text)),
    );
  }

  Future<void> _search(String text) async {
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _failure = null;
    });
    try {
      final matches = await resolveGeocoder().search(text.trim());
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _searching = false;
        _results = matches;
        _failure =
            matches.isEmpty ? LocaleKeys.dashboard_place_noMatches.tr() : null;
      });
    } on Object {
      if (mounted && generation == _generation) {
        setState(() {
          _searching = false;
          _failure = LocaleKeys.dashboard_place_failed.tr();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 460),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(18),
          boxShadow: palette.cardShadow(raised: true),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: palette.sunken,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 17,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        autofocus: true,
                        style: DashboardType.body(palette),
                        cursorColor: palette.accent,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: LocaleKeys.dashboard_place_search.tr(),
                          hintStyle: DashboardType.body(
                            palette,
                            color: palette.textMuted,
                          ),
                        ),
                        onChanged: _schedule,
                        onSubmitted: (value) => unawaited(_search(value)),
                      ),
                    ),
                    if (_searching)
                      SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: _results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      child: Text(
                        _failure ?? LocaleKeys.dashboard_place_hint.tr(),
                        style: DashboardType.caption(palette),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      itemCount: _results.length,
                      itemBuilder: (_, index) {
                        final result = _results[index];
                        return _PlaceRowTile(
                          palette: palette,
                          result: result,
                          onTap: () => Navigator.of(context).pop(
                            DashboardPlace(
                              name: result.name,
                              latitude: result.point.latitude,
                              longitude: result.point.longitude,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRowTile extends StatefulWidget {
  const _PlaceRowTile({
    required this.palette,
    required this.result,
    required this.onTap,
  });

  final DashboardPalette palette;
  final GeocodeResult result;
  final VoidCallback onTap;

  @override
  State<_PlaceRowTile> createState() => _PlaceRowTileState();
}

class _PlaceRowTileState extends State<_PlaceRowTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final result = widget.result;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: _hovered ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                Icons.place_rounded,
                size: 16,
                color: palette.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.cardTitle(
                        palette,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (result.address.isNotEmpty &&
                        result.address != result.name)
                      Text(
                        result.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.caption(palette),
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
