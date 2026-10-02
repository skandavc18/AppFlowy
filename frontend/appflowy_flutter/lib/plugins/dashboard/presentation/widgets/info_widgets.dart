import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_place_picker.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/weather/weather_reading.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Everything else a dashboard can show.
///
/// The group exists so the next specialised widget — a portfolio value, a
/// build status, a workload chart — is a registration rather than a redesign.
void registerDashboardInfoWidgets() {
  DashboardWidgetRegistry.register(_weather);
}

const _keyPlace = 'place';
const _keyLatitude = 'latitude';
const _keyLongitude = 'longitude';
const _keyUnits = 'units';

final _weather = DashboardWidgetDefinition(
  type: 'weather',
  label: () => LocaleKeys.dashboard_widget_weather.tr(),
  description: () => LocaleKeys.dashboard_widget_weatherHint.tr(),
  icon: Icons.wb_sunny_rounded,
  group: DashboardWidgetGroup.info,
  defaultColumnSpan: 3,
  defaultRowSpan: 3,
  defaultAccent: DashboardAccent.blue,
  // A little piece of sky rather than a box with a number in it.
  surface: DashboardSurface.gradient,
  identity: DashboardAccent.blue,
  slashName: 'weather',
  keywords: const ['weather', 'forecast', 'temperature', 'rain', 'outside'],
  builder: (context) => _WeatherBody(context: context),
  configure: (context) => [
    DashboardConfigPlace(
      label: LocaleKeys.dashboard_config_place.tr(),
      hint: LocaleKeys.dashboard_config_placeHint.tr(),
      place: context.spec.setting(_keyPlace),
      onChanged: (name, latitude, longitude) => context.setSettings({
        _keyPlace: name.isEmpty ? null : name,
        _keyLatitude: latitude,
        _keyLongitude: longitude,
      }),
    ),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_units.tr(),
      value: context.spec.setting(_keyUnits, fallback: 'celsius'),
      choices: [
        DashboardChoice(
          value: 'celsius',
          label: LocaleKeys.dashboard_weather_celsius.tr(),
        ),
        DashboardChoice(
          value: 'fahrenheit',
          label: LocaleKeys.dashboard_weather_fahrenheit.tr(),
        ),
      ],
      onChanged: (value) => context.setSettings({_keyUnits: value}),
    ),
    DashboardConfigNote(
      label: LocaleKeys.dashboard_weather_source.tr(),
      icon: Icons.info_outline_rounded,
    ),
  ],
);

/// One reading of the weather, as it came back.
typedef _Weather = WeatherReading;

class _WeatherBody extends StatefulWidget {
  const _WeatherBody({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_WeatherBody> createState() => _WeatherBodyState();
}

class _WeatherBodyState extends State<_WeatherBody> {
  _Weather? _weather;
  bool _loading = false;
  String? _failure;
  String _readFor = '';

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(_WeatherBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_key != _readFor ||
        oldWidget.context.refreshToken != widget.context.refreshToken) {
      unawaited(_read());
    }
  }

  String get _key => '${widget.context.spec.setting(_keyPlace)}|'
      '${widget.context.spec.setting(_keyUnits, fallback: 'celsius')}';

  /// Nothing leaves the machine until a place has actually been chosen.
  Future<void> _read() async {
    final spec = widget.context.spec;
    final place = spec.setting(_keyPlace).trim();
    _readFor = _key;
    if (place.isEmpty) {
      setState(() {
        _weather = null;
        _failure = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });

    try {
      var latitude = spec.settings[_keyLatitude];
      var longitude = spec.settings[_keyLongitude];
      if (latitude is! num || longitude is! num) {
        // A dashboard written before the picker existed, or a name typed by
        // hand, still resolves rather than sitting there saying nothing.
        final matches = await resolveGeocoder().search(place, limit: 1);
        if (matches.isEmpty) {
          throw StateError('no such place');
        }
        latitude = matches.first.point.latitude;
        longitude = matches.first.point.longitude;
        if (mounted) {
          widget.context.setSettings({
            _keyLatitude: latitude,
            _keyLongitude: longitude,
          });
        }
      }

      final fahrenheit =
          spec.setting(_keyUnits, fallback: 'celsius') == 'fahrenheit';
      final weather = await readWeather(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        fahrenheit: fahrenheit,
      );
      if (mounted) {
        setState(() {
          _weather = weather;
          _loading = false;
        });
      }
    } on Object catch (error) {
      Log.warn('The weather could not be read: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _failure = LocaleKeys.dashboard_weather_unavailable.tr();
        });
      }
    }
  }

  Future<void> _choosePlace() async {
    final place = await showDashboardPlacePicker(
      context: context,
      palette: widget.context.palette,
      initialQuery: widget.context.spec.setting(_keyPlace),
    );
    if (place == null) {
      return;
    }
    widget.context.setSettings({
      _keyPlace: place.name,
      _keyLatitude: place.latitude,
      _keyLongitude: place.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.context.palette;
    final tone = widget.context.tone;
    final place = widget.context.spec.setting(_keyPlace).trim();
    if (place.isEmpty) {
      return DashboardPlaceholder(
        palette: palette,
        icon: Icons.location_on_outlined,
        color: tone.label,
        message: LocaleKeys.dashboard_weather_pickPlace.tr(),
        action: LocaleKeys.dashboard_config_choose.tr(),
        onAction: () => unawaited(_choosePlace()),
      );
    }
    final weather = _weather;
    if (weather == null) {
      return DashboardPlaceholder(
        palette: palette,
        icon: _loading ? Icons.cloud_queue_rounded : Icons.cloud_off_rounded,
        color: tone.label,
        message: _loading
            ? LocaleKeys.dashboard_widget_reading.tr()
            : (_failure ?? LocaleKeys.dashboard_weather_unavailable.tr()),
        action: _loading ? null : LocaleKeys.dashboard_place_change.tr(),
        onAction: () => unawaited(_choosePlace()),
      );
    }

    final unit = widget.context.spec.setting(_keyUnits, fallback: 'celsius') ==
            'fahrenheit'
        ? '°F'
        : '°C';
    String degrees(double value) =>
        '${formatDashboardNumber(value, decimals: 0)}°';

    // A small piece of sky: where, how warm, what it is doing, and the
    // day's range — the temperature large, everything else quiet around it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.near_me_rounded, size: 13, color: tone.label),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                place,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardType.eyebrow(palette, color: tone.label),
              ),
            ),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          formatDashboardNumber(
                            weather.temperature,
                            decimals: 0,
                          ),
                          style: DashboardType.display(
                            palette,
                            size: 56,
                            weight: FontWeight.w300,
                            color: tone.figure,
                          ),
                        ),
                        Text(
                          unit,
                          style: DashboardType.display(
                            palette,
                            size: 22,
                            color: tone.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 6),
                child: Icon(
                  weatherIconFor(weather.code),
                  size: 38,
                  color: tone.strong,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            _conditionOf(weather.code),
            LocaleKeys.dashboard_weather_high.tr(
              args: [degrees(weather.high)],
            ),
            LocaleKeys.dashboard_weather_low.tr(
              args: [degrees(weather.low)],
            ),
          ].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardType.caption(palette, color: tone.inkSoft)
              .copyWith(fontSize: 12.5),
        ),
      ],
    );
  }
}

/// WMO weather codes, in words.
String _conditionOf(int code) {
  if (code == 0) {
    return LocaleKeys.dashboard_weather_clear.tr();
  }
  if (code <= 3) {
    return LocaleKeys.dashboard_weather_cloudy.tr();
  }
  if (code <= 48) {
    return LocaleKeys.dashboard_weather_fog.tr();
  }
  if (code <= 67 || (code >= 80 && code <= 82)) {
    return LocaleKeys.dashboard_weather_rain.tr();
  }
  if (code <= 79 || (code >= 85 && code <= 86)) {
    return LocaleKeys.dashboard_weather_snow.tr();
  }
  return LocaleKeys.dashboard_weather_storm.tr();
}
