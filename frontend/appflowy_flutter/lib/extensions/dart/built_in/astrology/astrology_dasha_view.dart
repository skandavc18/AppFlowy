import 'dart:ui' as ui;

import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'astrology_model.dart';
import 'astrology_style.dart';
import 'astrology_time.dart';
import 'vimshottari.dart';

/// A full-card navigator for the complete, unclipped 120-year birth cycle.
/// [at] fixes the reading instant. Otherwise it is sampled on opening and when
/// Current period is pressed; there is no timer and chart inputs are read-only.
///
/// Navigation contracts: only `dasha-page-$path` is mounted, where a path is
/// lower-case lord names joined by hyphens, or `root` for all nine Mahadashas.
/// Every `dasha-open-$path` tile opens a page, including Sookshma leaves.
/// `dasha-back` pops one level; `dasha-breadcrumb-root` clears the path;
/// `dasha-breadcrumb-$index` selects that zero-based ancestor (inclusive).
/// `dasha-selected-title` and `dasha-detail-start/end` identify the overview.
/// Reading-instant changes update statuses, not the trail or scroll position.
/// A different chart identity resets the trail. Only this card's scroll and
/// focus nodes are owned here; the existing enlarged-view host is unchanged.
class AstrologyDashaTable extends StatefulWidget {
  const AstrologyDashaTable({super.key, required this.chart, this.at});

  final AstrologyChart chart;
  final DateTime? at;

  @override
  State<AstrologyDashaTable> createState() => _AstrologyDashaTableState();
}

class _AstrologyDashaTableState extends State<AstrologyDashaTable> {
  final _scroll = ScrollController();
  final _navigatorFocus = FocusNode(
    debugLabel: 'Dasha navigator',
    skipTraversal: true,
  );
  final _headingFocus = FocusNode(
    debugLabel: 'Dasha heading',
    skipTraversal: true,
  );
  final _backFocus = FocusNode(debugLabel: 'Dasha back');
  late List<DashaPeriod> _roots;
  late List<DashaPeriod> _active;
  late DateTime _at;
  List<DashaPeriod> _stack = [];
  bool _details = false;
  int _navigationRevision = 0;

  @override
  void initState() {
    super.initState();
    _readChart();
  }

  void _readChart() {
    _roots = vimshottariPeriods(
      birthUtc: widget.chart.utc,
      moonLongitude: widget.chart.planet(VedicBody.moon).longitude,
      yearDays: widget.chart.input.dashaYearDays,
    );
    _stack = [];
    _readInstant();
  }

  void _readInstant() {
    _at = (widget.at ?? DateTime.now()).toUtc();
    _active = dashaAt(_roots, _at);
  }

  @override
  void didUpdateWidget(covariant AstrologyDashaTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chart, widget.chart)) {
      _readChart();
      _resetViewport(restoreFocus: _navigatorFocus.hasFocus);
    } else if (oldWidget.at != widget.at) {
      _readInstant();
    }
  }

  void _navigate(Iterable<DashaPeriod> path) {
    final restoreFocus = _navigatorFocus.hasFocus;
    final next = List<DashaPeriod>.of(path);
    setState(() => _stack = next);
    _resetViewport(restoreFocus: restoreFocus);
  }

  void _resetViewport({required bool restoreFocus}) {
    final revision = ++_navigationRevision;
    // A new chart can arrive during an ancestor's build. Wait until layout is
    // complete before dispatching scroll notifications or moving focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _navigationRevision) return;
      // Never ensureVisible: that also scrolls an enclosing dashboard/editor.
      if (_scroll.hasClients && _scroll.offset != 0) _scroll.jumpTo(0);
      if (restoreFocus) {
        (_stack.isEmpty ? _headingFocus : _backFocus).requestFocus();
      }
    });
  }

  void _showCurrent() {
    _readInstant();
    _navigate(_active);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        _stack.isNotEmpty &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed &&
        ((event.logicalKey == LogicalKeyboardKey.escape &&
                !keyboard.isAltPressed) ||
            (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                keyboard.isAltPressed))) {
      _navigate(_stack.take(_stack.length - 1));
      return KeyEventResult.handled;
    }
    // In particular, Backspace remains available to text/editing shortcuts.
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _navigatorFocus.dispose();
    _headingFocus.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final theme = Theme.of(context);
    final selected = _stack.isEmpty ? null : _stack.last;
    final path = _path(_stack);
    final leaf = selected?.level == vimshottariLevelNames.length - 1;
    final visible = selected == null
        ? _roots
        : leaf
            ? const <DashaPeriod>[]
            : selected.children;

    return ColoredBox(
      key: const ValueKey('astrology-dasha-surface'),
      color: palette.surface,
      child: Theme(
        data: theme.copyWith(
          hoverColor: palette.hover,
          focusColor: palette.selection,
          highlightColor: palette.hover,
          splashColor: palette.selection,
          colorScheme: theme.colorScheme.copyWith(
            surfaceTint: palette.surface.withValues(alpha: 0),
          ),
          tooltipTheme: theme.tooltipTheme.copyWith(
            decoration: BoxDecoration(
              color: palette.raised,
              border: Border.all(color: palette.line),
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: _style(context, palette.ink, 12),
          ),
        ),
        child: FocusTraversalGroup(
          child: Focus(
            key: const ValueKey('dasha-navigator-focus'),
            focusNode: _navigatorFocus,
            onKeyEvent: _onKeyEvent,
            child: SizedBox.expand(
              child: ScrollConfiguration(
                behavior: NoScrollbarBehavior(ScrollConfiguration.of(context)),
                child: SingleChildScrollView(
                  key: const ValueKey('astrology-dasha-scroll'),
                  controller: _scroll,
                  primary: false,
                  padding: const EdgeInsets.all(12),
                  // The header scrolls too: even 220×100 at 2× text has no
                  // fixed-height toolbar or outer-viewport overflow.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(context),
                      if (_stack.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _breadcrumbs(context),
                      ],
                      const SizedBox(height: 14),
                      // Deliberately no AnimatedSwitcher/retained old pages:
                      // one route, no duplicate focus targets, no motion even
                      // with disableAnimations or accessibleNavigation enabled.
                      Column(
                        key: ValueKey('dasha-page-$path'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (selected != null) ...[
                            _DashaOverview(
                              period: selected,
                              path: path,
                              chart: widget.chart,
                              at: _at,
                            ),
                            const SizedBox(height: 14),
                          ],
                          if (_active.isEmpty) ...[
                            Text(
                              'Reading date is outside this 120-year cycle.',
                              key: const ValueKey('dasha-outside-cycle'),
                              style: _style(context, palette.muted, 12),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_details) ...[
                            _DashaDetails(
                              chart: widget.chart,
                              first: _roots.first,
                              at: _at,
                            ),
                            const SizedBox(height: 14),
                          ],
                          if (leaf)
                            Text(
                              'Finest supported level',
                              key: const ValueKey('dasha-leaf-note'),
                              style: _style(context, palette.muted, 12),
                            )
                          else ...[
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    vimshottariLevelNames[selected == null
                                        ? 0
                                        : selected.level + 1],
                                    key: const ValueKey('dasha-list-heading'),
                                    style: _style(context, palette.ink, 13),
                                  ),
                                ),
                                Text(
                                  '${visible.length} periods',
                                  style: _style(context, palette.muted, 11),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final period in visible)
                              _DashaTile(
                                period: period,
                                path: _path([..._stack, period]),
                                input: widget.chart.input,
                                at: _at,
                                onOpen: () => _navigate([..._stack, period]),
                              ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Focus(
              key: const ValueKey('dasha-heading-focus'),
              focusNode: _headingFocus,
              child: Semantics(
                header: true,
                child: Text(
                  'Vimshottari',
                  style: _style(context, palette.ink, 18),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '120-year cycle · 4 levels',
              style: _style(context, palette.muted, 12),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _DashaAction(
              id: 'dasha-current-period',
              label: 'Current period',
              onPressed: _showCurrent,
            ),
            _DashaAction(
              id: 'dasha-details',
              label: 'Details',
              selected: _details,
              onPressed: () => setState(() => _details = !_details),
            ),
          ],
        ),
      ],
    );
  }

  Widget _breadcrumbs(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return Wrap(
      key: const ValueKey('dasha-breadcrumbs'),
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _DashaAction(
          id: 'dasha-back',
          label: 'Back',
          icon: Icons.arrow_back_rounded,
          focusNode: _backFocus,
          onPressed: () => _navigate(_stack.take(_stack.length - 1)),
        ),
        _DashaAction(
          id: 'dasha-breadcrumb-root',
          label: 'All dashas',
          onPressed: () => _navigate(const []),
        ),
        for (var index = 0; index < _stack.length; index++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: palette.muted,
                ),
              ),
              Flexible(
                child: Tooltip(
                  message: '${_stack[index].lord.label} '
                      '${vimshottariLevelNames[_stack[index].level]}',
                  excludeFromSemantics: true,
                  child: _DashaAction(
                    id: 'dasha-breadcrumb-$index',
                    label: _stack[index].lord.label,
                    semanticsLabel: '${_stack[index].lord.label} '
                        '${vimshottariLevelNames[_stack[index].level]}',
                    selected: index == _stack.length - 1,
                    onPressed: () => _navigate(_stack.take(index + 1)),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _DashaTile extends StatelessWidget {
  const _DashaTile({
    required this.period,
    required this.path,
    required this.input,
    required this.at,
    required this.onOpen,
  });

  final DashaPeriod period;
  final String path;
  final AstrologyInput input;
  final DateTime at;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final current = period.contains(at);
    final radius = BorderRadius.circular(10);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        key: ValueKey('dasha-semantics-$path'),
        container: true,
        button: true,
        selected: current,
        onTap: onOpen,
        hint: 'Open ${period.lord.label} '
            '${vimshottariLevelNames[period.level]}',
        child: Material(
          key: ValueKey('dasha-card-$path'),
          color: current ? palette.selection : palette.control,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: palette.line.withValues(alpha: 0.55)),
          ),
          clipBehavior: Clip.antiAlias,
          textStyle: _style(context, palette.ink, 13),
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            child: InkWell(
              key: ValueKey('dasha-open-$path'),
              onTap: onOpen,
              excludeFromSemantics: true,
              borderRadius: radius,
              hoverColor: palette.hover,
              focusColor: palette.selection,
              highlightColor: palette.hover,
              splashFactory: NoSplash.splashFactory,
              child: SelectionContainer.disabled(
                // Plain Text is intentional: selectable children consume
                // pointer gestures intended for the entire rectangular tile.
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _PlanetDot(body: period.lord),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  period.lord.label,
                                  key: ValueKey('dasha-$path-title'),
                                  style: _style(context, palette.ink, 14),
                                ),
                                if (current)
                                  _DashaPill(
                                    id: 'dasha-current-$path',
                                    label: 'Current',
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          ExcludeSemantics(
                            child: Icon(
                              Icons.chevron_right_rounded,
                              key: ValueKey('dasha-chevron-$path'),
                              size: 18,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _DashaDates(
                          prefix: 'dasha-$path', input: input, period: period),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashaOverview extends StatelessWidget {
  const _DashaOverview({
    required this.period,
    required this.path,
    required this.chart,
    required this.at,
  });

  final DashaPeriod period;
  final String path;
  final AstrologyChart chart;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final current = period.contains(at);
    return DecoratedBox(
      key: const ValueKey('dasha-overview'),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 9, right: 8),
                  child: _PlanetDot(body: period.lord),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      '${period.lord.label} ${vimshottariLevelNames[period.level]}',
                      key: const ValueKey('dasha-selected-title'),
                      style: _style(context, palette.ink, 18),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                KeyedSubtree(
                  key: const ValueKey('dasha-detail-status'),
                  child: _DashaPill(
                    id: current ? 'dasha-current-$path' : 'dasha-status-$path',
                    label: current
                        ? 'Current'
                        : at.isBefore(period.start)
                            ? 'Upcoming'
                            : 'Finished',
                    selected: current,
                  ),
                ),
                _DashaPill(
                  id: 'dasha-detail-duration',
                  label: _duration(period.end.difference(period.start)),
                ),
                if (period.contains(chart.utc))
                  const _DashaPill(label: 'Contains birth')
                else if (!period.end.isAfter(chart.utc))
                  const _DashaPill(label: 'Entirely before birth'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                  height: 1, color: palette.line.withValues(alpha: 0.55)),
            ),
            _DashaDates(
                prefix: 'dasha-detail', input: chart.input, period: period),
            const SizedBox(height: 10),
            Text(
              _zoneLabel(chart.input),
              key: const ValueKey('dasha-detail-zone'),
              style: _style(context, palette.muted, 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashaDates extends StatelessWidget {
  const _DashaDates({
    required this.prefix,
    required this.input,
    required this.period,
  });

  final String prefix;
  final AstrologyInput input;
  final DashaPeriod period;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final start = _DashaDate(
            id: '$prefix-start',
            label: 'Start',
            input: input,
            utc: period.start,
          );
          final end = _DashaDate(
            id: '$prefix-end',
            label: 'End',
            input: input,
            utc: period.end,
          );
          final endpointWidth =
              180 * MediaQuery.textScalerOf(context).scale(13) / 13;
          if (constraints.maxWidth >= endpointWidth * 2 + 16) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: start),
                const SizedBox(width: 16),
                Expanded(child: end),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [start, const SizedBox(height: 16), end],
          );
        },
      );
}

class _DashaDate extends StatelessWidget {
  const _DashaDate({
    required this.id,
    required this.label,
    required this.input,
    required this.utc,
  });

  final String id;
  final String label;
  final AstrologyInput input;
  final DateTime utc;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          key: ValueKey('$id-label'),
          style: _style(context, palette.muted, 11),
        ),
        const SizedBox(height: 4),
        Text(
          _moment(input, utc),
          key: ValueKey(id),
          style: _style(context, palette.ink, 13),
        ),
      ],
    );
  }
}

class _DashaDetails extends StatelessWidget {
  const _DashaDetails(
      {required this.chart, required this.first, required this.at});

  final AstrologyChart chart;
  final DashaPeriod first;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final year = chart.input.dashaYearDays * Duration.microsecondsPerDay;
    final balance = first.end.difference(chart.utc).inMicroseconds / year;
    final elapsed = chart.utc.difference(first.start).inMicroseconds / year;
    return DecoratedBox(
      key: const ValueKey('dasha-convention-details'),
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Birth balance: ${first.lord.label} · '
              '${balance.toStringAsFixed(6)} years remaining',
              key: const ValueKey('dasha-birth-balance'),
              style: _style(context, palette.ink, 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Elapsed before birth: ${elapsed.toStringAsFixed(6)} years. '
              'The first Mahadasha and its children retain their full pre-birth '
              'durations; they are not clipped to birth.',
              key: const ValueKey('dasha-pre-birth-note'),
              style: _style(context, palette.muted, 12),
            ),
            const SizedBox(height: 8),
            Text(
              '${chart.input.dashaYearDays} days/year. Start is inclusive; '
              'end is exclusive. Dates use ${_zoneLabel(chart.input)} '
              'with the offset at each endpoint.',
              style: _style(context, palette.muted, 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Reading date: ${_moment(chart.input, at).replaceAll('\n', ' ')}',
              key: const ValueKey('dasha-reading-date'),
              style: _style(context, palette.muted, 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanetDot extends StatelessWidget {
  const _PlanetDot({required this.body});

  final VedicBody body;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AstrologyPalette.of(context).planetColor(body),
          shape: BoxShape.circle,
        ),
        child: const SizedBox(width: 7, height: 7),
      );
}

class _DashaPill extends StatelessWidget {
  const _DashaPill({this.id, required this.label, this.selected = false});

  final String? id;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? palette.selection : palette.control,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          key: id == null ? null : ValueKey(id!),
          style: _style(context, palette.ink, 11),
        ),
      ),
    );
  }
}

class _DashaAction extends StatelessWidget {
  const _DashaAction({
    required this.id,
    required this.label,
    required this.onPressed,
    this.icon,
    this.focusNode,
    this.semanticsLabel,
    this.selected = false,
  });

  final String id;
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final FocusNode? focusNode;
  final String? semanticsLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final text = Text(label, semanticsLabel: semanticsLabel);
    return Semantics(
      selected: selected,
      child: TextButton(
        key: ValueKey(id),
        focusNode: focusNode,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: palette.ink,
          backgroundColor: selected ? palette.selection : palette.control,
          textStyle: _style(context, palette.ink, 13),
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(
          animationDuration: Duration.zero,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.focused)
                ? palette.selection
                : palette.hover;
          }),
        ),
        child: icon == null
            ? text
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: 5),
                  Flexible(child: text),
                ],
              ),
      ),
    );
  }
}

String _path(Iterable<DashaPeriod> periods) => periods.isEmpty
    ? 'root'
    : periods.map((period) => period.lord.name).join('-');

String _two(int value) => value.toString().padLeft(2, '0');

/// Preserve fractional seconds as well as historical offset seconds. Each
/// endpoint is resolved independently by the shared timezone service.
String _moment(AstrologyInput input, DateTime utc) {
  final offset = AstrologyTime.offsetAt(input, utc);
  final local = utc.toUtc().add(offset);
  final micros = local.millisecond * 1000 + local.microsecond;
  final fraction = micros == 0 ? '' : '.${micros.toString().padLeft(6, '0')}';
  final offsetSeconds = offset.inSeconds.abs() % 60;
  return '${local.year.toString().padLeft(4, '0')}-${_two(local.month)}-${_two(local.day)}\n'
      '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}$fraction\n'
      'UTC${AstrologyTime.offsetLabel(offset)}'
      '${offsetSeconds == 0 ? '' : ':${_two(offsetSeconds)}'}';
}

String _zoneLabel(AstrologyInput input) {
  final zone = input.place?.timeZone;
  if (input.utcOffsetMinutes != null) {
    return '${zone == null || zone.isEmpty ? '' : '$zone · '}'
        'fixed UTC offset override';
  }
  return zone == null || zone.isEmpty ? 'Device time zone' : zone;
}

String _duration(Duration duration) {
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final micros = duration.inMicroseconds % Duration.microsecondsPerSecond;
  final fraction = micros == 0 ? '' : '.${micros.toString().padLeft(6, '0')}';
  return [
    if (duration.inDays > 0)
      '${duration.inDays} ${duration.inDays == 1 ? 'day' : 'days'}',
    if (hours > 0) '${hours}h',
    if (minutes > 0) '${minutes}m',
    if (seconds > 0 || micros > 0 || duration == Duration.zero)
      '$seconds${fraction}s',
  ].join(' ');
}

TextStyle _style(BuildContext context, Color color, double size) {
  final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
      .merge(DefaultTextStyle.of(context).style);
  return base.copyWith(
    color: color,
    fontSize: size,
    height: 1.45,
    fontFeatures: [
      ...?base.fontFeatures,
      const ui.FontFeature.tabularFigures(),
    ],
  );
}
