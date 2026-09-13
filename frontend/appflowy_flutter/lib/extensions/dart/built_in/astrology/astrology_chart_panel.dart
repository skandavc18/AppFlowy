import 'dart:async';

import 'package:flutter/material.dart';

import 'astrology_engine.dart';
import 'astrology_location.dart';
import 'astrology_model.dart';
import 'astrology_style.dart';
import 'astrology_tables.dart';
import 'vedic_chart_view.dart';

/// Extension lifecycle signal. A disabled extension stops timers/requests even
/// when an already mounted dashboard still holds its former widget builder.
abstract final class AstrologyRuntime {
  static final active = ValueNotifier<bool>(false);
}

typedef AstrologyCalculator = Future<AstrologyChart> Function(
  AstrologyInput input,
);

/// The same bounded, interactive content in a document and on a dashboard.
/// Read-only previews perform no location lookup or native initialization.
class AstrologyChartPanel extends StatefulWidget {
  const AstrologyChartPanel({
    super.key,
    required this.input,
    this.view = AstrologyView.chart,
    this.division = 1,
    this.preview = false,
    this.refreshToken = 0,
    this.onConfigure,
    this.calculator,
    this.locationService,
  });

  final AstrologyInput input;
  final AstrologyView view;
  final int division;
  final bool preview;
  final int refreshToken;
  final VoidCallback? onConfigure;
  final AstrologyCalculator? calculator;
  final AstrologyLocationService? locationService;

  @override
  State<AstrologyChartPanel> createState() => _AstrologyChartPanelState();
}

class _AstrologyChartPanelState extends State<AstrologyChartPanel>
    with WidgetsBindingObserver {
  AstrologyChart? _chart;
  String? _error;
  bool _loading = false;
  bool _resumed = true;
  int _generation = 0;
  Timer? _clock;

  bool get _enabled =>
      !widget.preview &&
      (AstrologyRuntime.active.value || widget.calculator != null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AstrologyRuntime.active.addListener(_lifecycleChanged);
    _restart();
  }

  @override
  void didUpdateWidget(AstrologyChartPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameInput(oldWidget.input, widget.input) ||
        oldWidget.preview != widget.preview ||
        oldWidget.refreshToken != widget.refreshToken) {
      _restart();
    }
  }

  static bool _sameInput(AstrologyInput a, AstrologyInput b) {
    if (identical(a, b)) return true;
    try {
      return a.fingerprint == b.fingerprint;
    } on Object {
      // Invalid numeric input cannot be JSON encoded. Let _load validate and
      // report it, including when recovering from a malformed saved setting.
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      _restart();
    } else {
      _clock?.cancel();
    }
  }

  void _lifecycleChanged() {
    if (!mounted) return;
    _restart();
    setState(() {});
  }

  void _restart({bool forceLocation = false}) {
    _generation++;
    _clock?.cancel();
    _clock = null;
    _chart = null;
    _error = null;
    _loading = false;
    if (!_enabled || !_resumed) return;
    unawaited(_load(forceLocation: forceLocation));
    if (widget.input.isTransit) {
      _clock = Timer.periodic(
        const Duration(minutes: 1),
        (_) {
          if (!_loading && _enabled && _resumed) unawaited(_load());
        },
      );
    }
  }

  Future<void> _load({bool forceLocation = false}) async {
    if (!_enabled || !mounted) return;
    final generation = ++_generation;
    _loading = true;
    try {
      var input = widget.input;
      input.validate();
      if (input.place == null) {
        final place =
            await (widget.locationService ?? AstrologyLocationService.instance)
                .current(force: forceLocation);
        if (!mounted || generation != _generation || !_enabled) return;
        input = input.copyWith(place: place);
      }
      if (input.isTransit) {
        // Every card on this dashboard shares one instant and one cached result.
        final now = DateTime.now().toUtc();
        input = input.copyWith(
          utc: DateTime.utc(
            now.year,
            now.month,
            now.day,
            now.hour,
            now.minute,
          ),
        );
      }
      final chart =
          await (widget.calculator ?? AstrologyEngine.instance.calculate)(
        input,
      );
      if (!mounted || generation != _generation || !_enabled) return;
      setState(
        () {
          _chart = chart;
          _error = null;
          _loading = false;
        },
      );
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(
        () {
          _chart = null;
          _error = error is FormatException ? error.message : '$error';
          _loading = false;
        },
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _clock?.cancel();
    AstrologyRuntime.active.removeListener(_lifecycleChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    if (widget.preview) {
      return _message(
        context,
        'Live ${widget.view.label.toLowerCase()} appear after you use this template. '
        'No location is requested in a preview.',
      );
    }
    if (!_enabled) {
      return _message(context, 'Enable Vedic astrology in Extensions.');
    }
    if (_error != null) return _message(context, _error!, error: true);
    final chart = _chart;
    if (chart == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return switch (widget.view) {
      AstrologyView.placements => AstrologyPlacementsTable(chart: chart),
      AstrologyView.panchanga => AstrologyPanchangaView(chart: chart),
      AstrologyView.dasha => AstrologyDashaTable(chart: chart),
      AstrologyView.shadbala => AstrologyShadbalaView(chart: chart),
      AstrologyView.ashtakavarga => AstrologyAshtakavargaView(
          chart: chart,
          style: widget.input.style,
        ),
      AstrologyView.chart => Column(
          children: [
            Expanded(
              child: VedicChartView(
                placements: chart.planets,
                ascendant: chart.ascendant,
                style: widget.input.style,
                division: widget.division,
                centerLabel: 'D-${widget.division}',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.input.isTransit ? 'Live transit · ' : ''}'
              '${chart.input.ayanamsaLabel} · '
              '${chart.utc.toIso8601String().substring(0, 19).replaceFirst('T', ' ')} UTC',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.muted,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
    };
  }

  Widget _message(BuildContext context, String text, {bool error = false}) {
    final palette = AstrologyPalette.of(context);
    return Center(
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                error ? Icons.location_off_rounded : Icons.auto_awesome_rounded,
                color: error ? palette.danger : palette.accent,
                size: 23,
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.muted),
              ),
              if (widget.onConfigure != null && !widget.preview)
                TextButton(
                  onPressed: widget.onConfigure,
                  child: const Text('Birth details / location'),
                ),
              if (error)
                TextButton(
                  onPressed: () {
                    _restart(forceLocation: true);
                    setState(() {});
                  },
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
