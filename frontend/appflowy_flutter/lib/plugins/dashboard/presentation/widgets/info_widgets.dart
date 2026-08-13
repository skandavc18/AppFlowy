import 'dart:async';
import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_place_picker.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
@immutable
class _Weather {
  const _Weather({
    required this.temperature,
    required this.high,
    required this.low,
    required this.code,
  });

  final double temperature;
  final double high;
  final double low;
  final int code;
}

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
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'current': 'temperature_2m,weather_code',
        'daily': 'temperature_2m_max,temperature_2m_min',
        'forecast_days': '1',
        'timezone': 'auto',
        if (fahrenheit) 'temperature_unit': 'fahrenheit',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw StateError('unexpected answer');
      }
      final current = body['current'];
      final daily = body['daily'];
      if (current is! Map || daily is! Map) {
        throw StateError('unexpected answer');
      }
      final weather = _Weather(
        temperature: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
        high: _firstNumber(daily['temperature_2m_max']),
        low: _firstNumber(daily['temperature_2m_min']),
        code: (current['weather_code'] as num?)?.round() ?? 0,
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

  static double _firstNumber(Object? value) =>
      value is List && value.isNotEmpty && value.first is num
          ? (value.first as num).toDouble()
          : 0;

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
    final place = widget.context.spec.setting(_keyPlace).trim();
    if (place.isEmpty) {
      return DashboardPlaceholder(
        palette: palette,
        icon: Icons.location_on_outlined,
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
    return Row(
      children: [
        Icon(
          _iconFor(weather.code),
          size: 34,
          color: widget.context.strong,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: DashboardFigure(
            value: formatDashboardNumber(weather.temperature, decimals: 0),
            suffix: unit,
            palette: palette,
            size: 28,
            caption: '$place · '
                '${formatDashboardNumber(weather.low, decimals: 0)}'
                '–${formatDashboardNumber(weather.high, decimals: 0)}$unit',
          ),
        ),
      ],
    );
  }

  /// WMO weather codes, as Open-Meteo reports them.
  IconData _iconFor(int code) {
    if (code == 0) {
      return Icons.wb_sunny_rounded;
    }
    if (code <= 3) {
      return Icons.wb_cloudy_rounded;
    }
    if (code <= 48) {
      return Icons.foggy;
    }
    if (code <= 67 || (code >= 80 && code <= 82)) {
      return Icons.water_drop_rounded;
    }
    if (code <= 79 || (code >= 85 && code <= 86)) {
      return Icons.ac_unit_rounded;
    }
    return Icons.thunderstorm_rounded;
  }
}
