import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

import 'astrology_dashboard_model.dart';
import 'astrology_dashboard_service.dart';
import 'astrology_style.dart';
import 'astrology_time.dart';

/// Saved-profile index for the template's library card, never the birth form.
/// The service reads actual child dashboards; there is no second catalogue.
/// Empty view ids (template previews) and disabled extensions perform no IO.
class AstrologyHoroscopeLibrary extends StatefulWidget {
  const AstrologyHoroscopeLibrary({
    super.key,
    required this.libraryViewId,
    required this.enabled,
    required this.onOpen,
    this.refreshToken = 0,
    this.service,
    this.listenerFactory,
  });

  final String libraryViewId;
  final bool enabled;
  final ValueChanged<ViewPB> onOpen;
  final int refreshToken;
  final AstrologyDashboardService? service;
  final ViewListener Function(String viewId)? listenerFactory;

  @override
  State<AstrologyHoroscopeLibrary> createState() =>
      _AstrologyHoroscopeLibraryState();
}

class _AstrologyHoroscopeLibraryState extends State<AstrologyHoroscopeLibrary> {
  List<ViewPB> _people = const [];
  ViewListener? _libraryListener;
  final _personListeners = <String, ViewListener>{};
  String? _error;
  bool _loading = false;
  int _scope = 0;
  int _request = 0;

  bool get _canLoad => widget.enabled && widget.libraryViewId.trim().isNotEmpty;

  ViewListener _listener(String id) =>
      widget.listenerFactory?.call(id) ?? ViewListener(viewId: id);

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant AstrologyHoroscopeLibrary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryViewId != widget.libraryViewId ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.service != widget.service ||
        oldWidget.listenerFactory != widget.listenerFactory) {
      _bind();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_load());
    }
  }

  void _stopListeners() {
    unawaited(_libraryListener?.stop());
    _libraryListener = null;
    for (final listener in _personListeners.values) {
      unawaited(listener.stop());
    }
    _personListeners.clear();
  }

  void _bind() {
    _scope++;
    _request++;
    _stopListeners();
    // Never show another library's birth details during a scope change.
    _people = const [];
    _error = null;
    _loading = false;
    if (!_canLoad) return;
    final scope = _scope;
    _libraryListener = _listener(widget.libraryViewId)
      ..start(onViewChildViewsUpdated: (_) => _notified(scope));
    unawaited(_load());
  }

  void _notified(int scope) {
    if (mounted && _canLoad && scope == _scope) unawaited(_load());
  }

  void _watchPeople(List<ViewPB> people) {
    final ids =
        people.map((person) => person.id).where((id) => id.isNotEmpty).toSet();
    for (final id in _personListeners.keys.toList()) {
      if (!ids.contains(id)) unawaited(_personListeners.remove(id)!.stop());
    }
    final scope = _scope;
    for (final id in ids) {
      if (_personListeners.containsKey(id)) continue;
      // Birth details can change without a membership change on the parent.
      _personListeners[id] = _listener(id)
        ..start(
          onViewUpdated: (_) => _notified(scope),
          onViewDeleted: (_) => _notified(scope),
          onViewMoveToTrash: (_) => _notified(scope),
        );
    }
  }

  Future<void> _load() async {
    if (!mounted || !_canLoad) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people =
          await (widget.service ?? AstrologyDashboardService.instance)
              .people(widget.libraryViewId);
      if (!mounted || !_canLoad || request != _request) return;
      _watchPeople(people);
      setState(() {
        _people = List.unmodifiable(people);
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || !_canLoad || request != _request) return;
      setState(() {
        _error = 'Could not read saved horoscopes. $error';
        _loading = false;
      });
    }
  }

  void _open(ViewPB person, int scope) {
    if (!mounted || !_canLoad || scope != _scope) return;
    // An old row callback must not open a removed or replaced record.
    for (final current in _people) {
      if (current.id.isNotEmpty && current.id == person.id) {
        widget.onOpen(current);
        return;
      }
    }
  }

  @override
  void dispose() {
    _scope++;
    _request++;
    _stopListeners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    return AstrologyHoroscopeTable(
      people: _people,
      loading: _loading,
      error: _error,
      onOpen: _canLoad ? (person) => _open(person, scope) : null,
      onRefresh: !_canLoad || _loading
          ? null
          : () {
              if (mounted && _canLoad && !_loading && scope == _scope) {
                unawaited(_load());
              }
            },
      emptyMessage: widget.enabled
          ? null
          : 'Enable Vedic astrology to read saved horoscopes.',
    );
  }
}

/// Read-only, whole-row navigation. The two owned scroll axes inherit the
/// dashboard's click-to-scroll gate, and never show desktop scrollbar rails.
class AstrologyHoroscopeTable extends StatefulWidget {
  const AstrologyHoroscopeTable({
    super.key,
    required this.people,
    required this.onOpen,
    this.onRefresh,
    this.loading = false,
    this.error,
    this.emptyMessage,
  });

  final List<ViewPB> people;
  final ValueChanged<ViewPB>? onOpen;
  final VoidCallback? onRefresh;
  final bool loading;
  final String? error;
  final String? emptyMessage;

  @override
  State<AstrologyHoroscopeTable> createState() =>
      _AstrologyHoroscopeTableState();
}

class _AstrologyHoroscopeTableState extends State<AstrologyHoroscopeTable> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.ink,
          fontSize: 13,
          height: 1.4,
        );
    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final summaries = widget.people.map(_HoroscopeSummary.fromView).toList();
    // Keep the library scope captured by this row. Reading widget.onOpen
    // later could route an old click into a different library with the same ID.
    final onOpen = widget.onOpen;
    return ScrollConfiguration(
      behavior: NoScrollbarBehavior(ScrollConfiguration.of(context)),
      child: Material(
        key: const ValueKey('astrology-horoscopes-surface'),
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          key: const ValueKey('astrology-horoscopes-scroll'),
          controller: _vertical,
          primary: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(
                constraints.hasBoundedWidth ? constraints.maxWidth : 720.0,
                720.0 * scale,
              );
              final contentWidth = width - 24 - 3 * 20;
              final widths = [
                contentWidth * 0.24,
                contentWidth * 0.20,
                contentWidth * 0.25,
                contentWidth * 0.31,
              ];
              final horoscopeLabel =
                  widget.people.length == 1 ? 'horoscope' : 'horoscopes';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '${widget.people.length} saved $horoscopeLabel',
                          key: const ValueKey('astrology-horoscopes-count'),
                          style: style?.copyWith(color: palette.muted),
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('astrology-horoscopes-refresh'),
                        onPressed: widget.loading ? null : widget.onRefresh,
                        style: TextButton.styleFrom(
                          foregroundColor: palette.accent,
                          disabledForegroundColor: palette.muted,
                          overlayColor: palette.hover,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(
                          widget.loading
                              ? 'Refreshing…'
                              : widget.error == null
                                  ? 'Refresh'
                                  : 'Retry',
                        ),
                      ),
                    ],
                  ),
                  if (widget.error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          widget.error!,
                          key: const ValueKey('astrology-horoscopes-error'),
                          style: style?.copyWith(color: palette.danger),
                        ),
                      ),
                    ),
                  SingleChildScrollView(
                    key: const ValueKey(
                      'astrology-horoscopes-horizontal-scroll',
                    ),
                    controller: _horizontal,
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      key: const ValueKey('astrology-horoscopes-table'),
                      showCheckboxColumn: false,
                      horizontalMargin: 12,
                      columnSpacing: 20,
                      headingRowHeight: math.max(40, 30 * scale + 12),
                      dataRowMinHeight: 60,
                      dataRowMaxHeight: double.infinity,
                      headingTextStyle: style?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w500,
                      ),
                      dataTextStyle: style,
                      headingRowColor: WidgetStatePropertyAll(palette.control),
                      dataRowColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.focused) ||
                            states.contains(WidgetState.pressed)) {
                          return palette.selection;
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return palette.hover;
                        }
                        // The Material already paints the themed surface.
                        // An opaque TableRow decoration would cover its ink.
                        return Colors.transparent;
                      }),
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: palette.line.withValues(alpha: 0.45),
                          width: 0.5,
                        ),
                      ),
                      columns: [
                        for (final entry in const [
                          'Name',
                          'Date of birth',
                          'Time of birth',
                          'Place of birth',
                        ].indexed)
                          DataColumn(
                            label: SizedBox(
                              width: widths[entry.$1],
                              child: Text(entry.$2),
                            ),
                          ),
                      ],
                      rows: [
                        for (final summary in summaries)
                          DataRow(
                            key: ValueKey(
                              'astrology-horoscope-${summary.view.id}',
                            ),
                            onSelectChanged:
                                onOpen == null || summary.view.id.isEmpty
                                    ? null
                                    : (_) {
                                        if (mounted && widget.onOpen != null) {
                                          onOpen(summary.view);
                                        }
                                      },
                            cells: [
                              _cell(
                                summary,
                                'name',
                                summary.name,
                                widths[0],
                                hint: 'Open ${summary.name} dashboard',
                              ),
                              _cell(summary, 'date', summary.date, widths[1]),
                              _cell(
                                summary,
                                'time',
                                summary.time,
                                widths[2],
                                secondary: summary.zone,
                              ),
                              _cell(
                                summary,
                                'place',
                                summary.place,
                                widths[3],
                                openIcon: onOpen != null &&
                                    summary.view.id.isNotEmpty,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (widget.people.isEmpty && widget.error == null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Semantics(
                        liveRegion: widget.loading,
                        child: Text(
                          widget.loading
                              ? 'Reading saved horoscopes…'
                              : widget.emptyMessage ??
                                  'Generate a chart above, then save it '
                                      'with a name. Each person appears here '
                                      'and as a subpage.',
                          key: const ValueKey('astrology-horoscopes-empty'),
                          style: style?.copyWith(color: palette.muted),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  DataCell _cell(
    _HoroscopeSummary summary,
    String field,
    String text,
    double width, {
    String? secondary,
    String? hint,
    bool openIcon = false,
  }) {
    final palette = AstrologyPalette.of(context);
    return DataCell(
      SizedBox(
        width: width,
        child: Tooltip(
          message: hint ?? [text, if (secondary != null) secondary].join('\n'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        key: ValueKey(
                          'astrology-horoscope-${summary.view.id}-$field',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (secondary != null)
                        Text(
                          secondary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ),
                if (openIcon) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: palette.muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoroscopeSummary {
  const _HoroscopeSummary(
    this.view,
    this.name,
    this.date,
    this.time,
    this.place,
    this.zone,
  );

  factory _HoroscopeSummary.fromView(ViewPB view) {
    var name = view.name.trim().isEmpty ? 'Unnamed horoscope' : view.name;
    var date = 'Not saved';
    var time = 'Not saved';
    var place = 'Not saved';
    String? zone;
    try {
      final document = view.dashboard?.document;
      if (document == null) {
        throw const FormatException('Missing birth profile');
      }
      final input = astrologyInputFromDashboard(document);
      if (view.name.trim().isEmpty && input.name.trim().isNotEmpty) {
        name = input.name;
      }
      if (input.place?.name.trim().isNotEmpty ?? false) {
        place = input.place!.name;
      }
      input.validate();
      final utc = input.utc;
      if (utc != null) {
        // Do not substitute this computer's timezone for a missing birthplace.
        if (input.place == null && input.utcOffsetMinutes == null) {
          throw const FormatException('Missing birth timezone');
        }
        final local = AstrologyTime.localTime(input, utc);
        final offset = AstrologyTime.offsetAt(input, utc);
        date = '${local.year.toString().padLeft(4, '0')}-'
            '${_two(local.month)}-${_two(local.day)}';
        final fraction = local.millisecond * 1000 + local.microsecond;
        final fractionDigits = fraction == 0
            ? ''
            : fraction
                .toString()
                .padLeft(6, '0')
                .replaceFirst(RegExp(r'0+$'), '');
        time = '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}'
            '${fraction == 0 ? '' : '.$fractionDigits'}';
        final offsetSeconds = offset.inSeconds.abs() % 60;
        zone = 'UTC${AstrologyTime.offsetLabel(offset)}'
            '${offsetSeconds == 0 ? '' : ':${_two(offsetSeconds)}'}'
            '${input.utcOffsetMinutes == null ? '' : ' (manual)'}';
      }
    } on Object {
      // One bad saved profile must not hide everyone else or lose its link.
      date = 'Unavailable';
      time = 'Unavailable';
    }
    return _HoroscopeSummary(view, name, date, time, place, zone);
  }

  final ViewPB view;
  final String name;
  final String date;
  final String time;
  final String place;
  final String? zone;

  static String _two(int value) => value.toString().padLeft(2, '0');
}
