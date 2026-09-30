import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'astrology_model.dart';
import 'astrology_style.dart';
import 'astrology_time.dart';
import 'vimshottari.dart';

/// A full-card navigator for the complete, unclipped 120-year birth cycle,
/// laid out as a tree like JHora's Dasa listing: every opened period sits
/// indented under its parent, and the selected one lists its nine sub-periods
/// one level deeper.
/// [at] fixes the reading instant. Otherwise it is sampled on opening and when
/// Current period is pressed; there is no timer and chart inputs are read-only.
///
/// Navigation contracts: only `dasha-page-$path` is mounted, where a path is
/// lower-case lord names joined by hyphens, or `root` for all nine Mahadashas.
/// Every `dasha-open-$path` row opens a page, including Sookshma leaves.
/// `dasha-back` pops one level; `dasha-breadcrumb-root` clears the path;
/// `dasha-breadcrumb-$index` is an opened ancestor above the selected period
/// and selects it again (inclusive).
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
    final path = _path(_stack);

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
                  padding: const EdgeInsets.all(14),
                  // The header scrolls too: even 220×100 at 2× text has no
                  // fixed-height toolbar or outer-viewport overflow.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(context),
                      if (_active.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _running(context),
                      ],
                      if (_stack.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _navigation(),
                      ],
                      const SizedBox(height: 16),
                      // Deliberately no AnimatedSwitcher/retained old pages:
                      // one route, no duplicate focus targets, no motion even
                      // with disableAnimations or accessibleNavigation enabled.
                      Column(
                        key: ValueKey('dasha-page-$path'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                            const SizedBox(height: 16),
                          ],
                          _DashaTree(
                            roots: _roots,
                            trail: _stack,
                            chart: widget.chart,
                            at: _at,
                            onNavigate: _navigate,
                          ),
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: WorkspaceGlyph(Icons.view_timeline_rounded, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
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
                        style: _strong(context, palette.ink, 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '120-year cycle · 4 levels',
                    style: _style(context, palette.muted, 12),
                  ),
                ],
              ),
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
              icon: Icons.my_location_rounded,
              onPressed: _showCurrent,
            ),
            _DashaAction(
              id: 'dasha-details',
              label: 'Details',
              icon: Icons.info_outline_rounded,
              selected: _details,
              onPressed: () => setState(() => _details = !_details),
            ),
          ],
        ),
      ],
    );
  }

  /// The periods running at the reading instant, from Mahadasha down.
  Widget _running(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final label = widget.at == null
        ? 'Running now'
        : 'Running on ${_cardDate(widget.chart.input, _at, time: true)}';
    return Semantics(
      label: '$label: '
          '${_active.map((period) => period.lord.label).join(', ')}',
      excludeSemantics: true,
      child: DecoratedBox(
        key: const ValueKey('dasha-running'),
        decoration: BoxDecoration(
          color: palette.control,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: _style(context, palette.muted, 12)),
              for (final (index, period) in _active.indexed) ...[
                if (index > 0)
                  WorkspaceGlyph(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: palette.muted,
                    role: WorkspaceGlyphRole.preserveInk,
                  ),
                _LordChip(body: period.lord),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The opened ancestors themselves are the breadcrumbs, inside the tree.
  Widget _navigation() => Wrap(
        key: const ValueKey('dasha-breadcrumbs'),
        spacing: 6,
        runSpacing: 6,
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
            icon: Icons.account_tree_rounded,
            onPressed: () => _navigate(const []),
          ),
        ],
      );
}

/// The opened trail as a tree, like JHora's nested Dasa listing: ancestors are
/// compact rows indented under their parents, the selected period opens into
/// its overview, and its nine sub-periods hang one level deeper on a rail.
class _DashaTree extends StatelessWidget {
  const _DashaTree({
    required this.roots,
    required this.trail,
    required this.chart,
    required this.at,
    required this.onNavigate,
  });

  final List<DashaPeriod> roots;
  final List<DashaPeriod> trail;
  final AstrologyChart chart;
  final DateTime at;
  final void Function(Iterable<DashaPeriod> path) onNavigate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final palette = AstrologyPalette.of(context);
          final scaler = MediaQuery.textScalerOf(context);
          final step = _treeIndent(constraints.maxWidth);
          final selected = trail.isEmpty ? null : trail.last;
          final depth = trail.length;
          final visible = selected == null ? roots : selected.children;
          Color rail(DashaPeriod parent) =>
              palette.planetTone(parent.lord).mark.withValues(alpha: 0.45);
          return Column(
            key: const ValueKey('dasha-tree'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, period) in trail.indexed)
                _TreeSlot(
                  depth: index,
                  step: step,
                  gap: index == 0 ? 0 : 8,
                  anchor: index == depth - 1
                      ? _DashaOverview.anchor(scaler)
                      : _DashaPathNode.anchor(scaler),
                  link: index == 0
                      ? null
                      : _TreeLink(rail(trail[index - 1]), _TreeLinkKind.last),
                  child: index == depth - 1
                      ? _DashaOverview(
                          period: period,
                          path: _path(trail),
                          chart: chart,
                          at: at,
                        )
                      : _DashaPathNode(
                          index: index,
                          period: period,
                          input: chart.input,
                          at: at,
                          onOpen: () => onNavigate(trail.take(index + 1)),
                        ),
                ),
              if (visible.isEmpty)
                _TreeSlot(
                  depth: math.max(0, depth - 1),
                  step: step,
                  gap: 12,
                  child: Text(
                    'Finest supported level',
                    key: const ValueKey('dasha-leaf-note'),
                    style: _style(context, palette.muted, 12),
                  ),
                )
              else ...[
                _TreeSlot(
                  depth: depth,
                  step: step,
                  gap: depth == 0 ? 0 : 14,
                  link: selected == null
                      ? null
                      : _TreeLink(rail(selected), _TreeLinkKind.through),
                  child: _heading(context, selected, visible.length),
                ),
                for (final (index, period) in visible.indexed)
                  _TreeSlot(
                    depth: depth,
                    step: step,
                    gap: index == 0 ? 10 : 6,
                    anchor: _DashaCard.anchor(scaler),
                    link: selected == null
                        ? null
                        : _TreeLink(
                            rail(selected),
                            index == visible.length - 1
                                ? _TreeLinkKind.last
                                : _TreeLinkKind.branch,
                            highlight: period.contains(at)
                                ? palette.planetTone(period.lord).mark
                                : null,
                          ),
                    child: _DashaCard(
                      period: period,
                      path: _path([...trail, period]),
                      input: chart.input,
                      at: at,
                      onOpen: () => onNavigate([...trail, period]),
                    ),
                  ),
              ],
            ],
          );
        },
      );

  /// "Antardashas in Sun Mahadasha · 9 periods", like JHora's
  /// "Sookshma-antardasas in this PD".
  Widget _heading(BuildContext context, DashaPeriod? parent, int count) {
    final palette = AstrologyPalette.of(context);
    final level = vimshottariLevelNames[parent == null ? 0 : parent.level + 1];
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(
            '${level}s',
            key: const ValueKey('dasha-list-heading'),
            style: _strong(context, palette.ink, 14),
          ),
        ),
        Text(
          parent == null
              ? '$count periods'
              : 'in ${parent.lord.label} '
                  '${vimshottariLevelNames[parent.level]} · $count periods',
          key: const ValueKey('dasha-list-context'),
          style: _style(context, palette.muted, 12),
        ),
      ],
    );
  }
}

/// Per-level indentation: a badge's width on roomy cards, a hint on narrow
/// ones, so four levels never squeeze the deepest rows unreadably.
double _treeIndent(double width) => width >= 880
    ? 44
    : width >= 600
        ? 30
        : width >= 400
            ? 20
            : 12;

enum _TreeLinkKind {
  /// The rail passes by, e.g. beside a list heading.
  through,

  /// A sibling follows: the rail continues past this row's elbow.
  branch,

  /// The rail ends in this row's elbow.
  last,
}

@immutable
class _TreeLink {
  const _TreeLink(this.color, this.kind, {this.highlight});

  final Color color;
  final _TreeLinkKind kind;

  /// Draws this row's elbow in the running period's color.
  final Color? highlight;

  @override
  bool operator ==(Object other) =>
      other is _TreeLink &&
      other.color == color &&
      other.kind == kind &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(color, kind, highlight);
}

/// One tree row, indented [depth] steps with its [link] to the parent's rail
/// painted in that indentation. The [gap] above belongs to the row, so the
/// rail also crosses it; [anchor] is the elbow's height within the child.
class _TreeSlot extends StatelessWidget {
  const _TreeSlot({
    required this.depth,
    required this.step,
    required this.child,
    this.gap = 0,
    this.anchor = 0,
    this.link,
  });

  final int depth;
  final double step;
  final double gap;
  final double anchor;
  final _TreeLink? link;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: EdgeInsetsDirectional.only(start: depth * step, top: gap),
      child: child,
    );
    final link = this.link;
    if (link == null || depth == 0) return body;
    return CustomPaint(
      painter: _TreeLinkPainter(
        link: link,
        rail: (depth - 1) * step + step / 2,
        start: depth * step,
        elbow: gap + anchor,
        direction: Directionality.of(context),
      ),
      child: body,
    );
  }
}

class _TreeLinkPainter extends CustomPainter {
  const _TreeLinkPainter({
    required this.link,
    required this.rail,
    required this.start,
    required this.elbow,
    required this.direction,
  });

  final _TreeLink link;
  final double rail;
  final double start;
  final double elbow;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double value) =>
        direction == TextDirection.rtl ? size.width - value : value;
    final stroke = Paint()
      ..color = link.color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = math.min(elbow, size.height);
    final radius = math.max(0.0, math.min(8.0, math.min(start - rail, y)));
    canvas.drawLine(
      Offset(x(rail), 0),
      Offset(
        x(rail),
        link.kind == _TreeLinkKind.last ? y - radius : size.height,
      ),
      stroke,
    );
    if (link.kind == _TreeLinkKind.through) return;
    final highlight = link.highlight;
    canvas.drawPath(
      Path()
        ..moveTo(x(rail), y - radius)
        ..quadraticBezierTo(x(rail), y, x(rail + radius), y)
        ..lineTo(x(start), y),
      highlight == null
          ? stroke
          : (Paint()
            ..color = highlight
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke),
    );
  }

  @override
  bool shouldRepaint(covariant _TreeLinkPainter oldDelegate) =>
      oldDelegate.link != link ||
      oldDelegate.rail != rail ||
      oldDelegate.start != start ||
      oldDelegate.elbow != elbow ||
      oldDelegate.direction != direction;
}

/// One period row: a light wash of its lord's color, a soft shadow that lifts
/// on hover or focus, and a progress track along its edge while it is running.
/// Roomy rows read across in one line, like JHora's listing.
class _DashaCard extends StatefulWidget {
  const _DashaCard({
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

  static const _padding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
  static const _badge = 34.0;

  static double _lead(TextScaler scaler) =>
      math.max(_badge, _line(scaler, 15) + 2 + _line(scaler, 11.5));

  /// Where the tree's elbow meets this card: its badge's center.
  static double anchor(TextScaler scaler) => _padding.top + _lead(scaler) / 2;

  @override
  State<_DashaCard> createState() => _DashaCardState();
}

class _DashaCardState extends State<_DashaCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final period = widget.period;
    final path = widget.path;
    final tone = palette.planetTone(period.lord);
    final current = period.contains(widget.at);
    final lifted = _hovered || _focused;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final radius = BorderRadius.circular(12);
    final withTime = period.level >= 2;
    final scaler = MediaQuery.textScalerOf(context);
    final lead = _DashaCard._lead(scaler);
    final forward =
        Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    return Semantics(
      key: ValueKey('dasha-semantics-$path'),
      container: true,
      button: true,
      selected: current,
      onTap: widget.onOpen,
      hint: 'Open ${period.lord.label} '
          '${vimshottariLevelNames[period.level]}',
      child: AnimatedContainer(
        key: ValueKey('dasha-card-fill-$path'),
        duration: motion,
        curve: Curves.easeOutCubic,
        transformAlignment: Alignment.center,
        transform: _lift(lifted ? -2 : 0, pressed: _pressed),
        decoration: _toneCard(
          palette,
          tone,
          radius: radius,
          strong: current,
          lifted: lifted,
          glow: current,
          focusRing: _focused && _keyboardFocus,
        ),
        child: Material(
          key: ValueKey('dasha-card-$path'),
          type: MaterialType.transparency,
          shape: RoundedRectangleBorder(borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          textStyle: _style(context, palette.ink, 13),
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            child: InkWell(
              key: ValueKey('dasha-open-$path'),
              onTap: widget.onOpen,
              onHover: (value) => setState(() => _hovered = value),
              onFocusChange: (value) => setState(() => _focused = value),
              onHighlightChanged: (value) => setState(() => _pressed = value),
              excludeFromSemantics: true,
              borderRadius: radius,
              hoverColor: tone.mark.withValues(alpha: 0),
              focusColor: tone.mark.withValues(alpha: 0.08),
              highlightColor: tone.mark.withValues(alpha: 0.06),
              splashFactory: NoSplash.splashFactory,
              child: SelectionContainer.disabled(
                // Plain Text is intentional: selectable children consume
                // pointer gestures intended for the entire rectangular card.
                child: Stack(
                  children: [
                    Padding(
                      padding: _DashaCard._padding,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final badge = SizedBox(
                            height: lead,
                            child: Center(
                              child: AnimatedScale(
                                scale: lifted ? 1.06 : 1,
                                duration: motion,
                                curve: Curves.easeOutBack,
                                child: _PlanetBadge(
                                  body: period.lord,
                                  strong: current,
                                  size: _DashaCard._badge,
                                ),
                              ),
                            ),
                          );
                          final title = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    period.lord.label,
                                    key: ValueKey('dasha-$path-title'),
                                    style: _strong(context, palette.ink, 15),
                                  ),
                                  if (current) ...[
                                    _DashaPill(
                                      id: 'dasha-current-$path',
                                      label: 'Current',
                                      tone: tone,
                                      selected: true,
                                    ),
                                    Text(
                                      '${(_elapsed(period, widget.at) * 100).floor()}% elapsed',
                                      key: ValueKey('dasha-progress-$path'),
                                      style: _style(context, palette.muted, 11),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${vimshottariLevelNames[period.level]} · '
                                '${_span(period, widget.input.dashaYearDays)}',
                                key: ValueKey('dasha-$path-span'),
                                style: _style(context, palette.muted, 11.5),
                              ),
                            ],
                          );
                          final start = _CardDate(
                            id: 'dasha-$path-start',
                            label: 'Start',
                            value: _cardDate(
                              widget.input,
                              period.start,
                              time: withTime,
                            ),
                          );
                          final end = _CardDate(
                            id: 'dasha-$path-end',
                            label: 'End',
                            value: _cardDate(
                              widget.input,
                              period.end,
                              time: withTime,
                            ),
                          );
                          final chevron = SizedBox(
                            height: lead,
                            child: Center(
                              child: ExcludeSemantics(
                                child: AnimatedSlide(
                                  offset:
                                      Offset(lifted ? 0.18 * forward : 0, 0),
                                  duration: motion,
                                  curve: Curves.easeOutCubic,
                                  child: WorkspaceGlyph(
                                    Icons.chevron_right_rounded,
                                    key: ValueKey('dasha-chevron-$path'),
                                    color: lifted ? tone.ink : palette.muted,
                                    role: WorkspaceGlyphRole.preserveInk,
                                  ),
                                ),
                              ),
                            ),
                          );
                          if (constraints.maxWidth >=
                              500 * scaler.scale(14) / 14) {
                            // Center the two-line dates on the badge's line.
                            final dateInset = math.max(
                              0.0,
                              (lead -
                                      _line(scaler, 11) -
                                      2 -
                                      _line(scaler, 13)) /
                                  2,
                            );
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                badge,
                                const SizedBox(width: 12),
                                Expanded(flex: 5, child: title),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 4,
                                  child: Padding(
                                    padding: EdgeInsets.only(top: dateInset),
                                    child: start,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 4,
                                  child: Padding(
                                    padding: EdgeInsets.only(top: dateInset),
                                    child: end,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                chevron,
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  badge,
                                  const SizedBox(width: 10),
                                  Expanded(child: title),
                                  const SizedBox(width: 6),
                                  chevron,
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: start),
                                  const SizedBox(width: 12),
                                  Expanded(child: end),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (current)
                      PositionedDirectional(
                        start: 0,
                        end: 0,
                        bottom: 0,
                        child: _DashaTrack(
                          fraction: _elapsed(period, widget.at),
                          color: tone.mark,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardDate extends StatelessWidget {
  const _CardDate({required this.id, required this.label, required this.value});

  final String id;
  final String label;
  final String value;

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
        const SizedBox(height: 2),
        Text(value, key: ValueKey(id), style: _style(context, palette.ink, 13)),
      ],
    );
  }
}

/// The share of a running period already elapsed at the reading instant.
class _DashaProgress extends StatelessWidget {
  const _DashaProgress({
    required this.id,
    required this.period,
    required this.at,
    required this.color,
  });

  final String id;
  final DashaPeriod period;
  final DateTime at;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final fraction = _elapsed(period, at);
    final percent = '${(fraction * 100).floor()}% elapsed';
    return Semantics(
      key: ValueKey(id),
      label: percent,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: color.withValues(alpha: 0.18)),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: fraction,
                    child: ColoredBox(color: color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(percent, style: _style(context, palette.muted, 11)),
        ],
      ),
    );
  }
}

/// A running row's progress along its bottom edge; the row's own text says
/// the percentage, so this line is decoration only.
class _DashaTrack extends StatelessWidget {
  const _DashaTrack({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: color.withValues(alpha: 0.16)),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: fraction,
                child: ColoredBox(color: color),
              ),
            ],
          ),
        ),
      );
}

/// A lord's abbreviation on a soft disc of its tone; a running period's disc
/// is filled with the vivid tone itself.
class _PlanetBadge extends StatelessWidget {
  const _PlanetBadge({required this.body, this.strong = false, this.size = 36});

  final VedicBody body;
  final bool strong;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = AstrologyPalette.of(context).planetTone(body);
    final base = strong ? tone.mark : tone.chip;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Lit from above, like a bead rather than a flat dot.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(base, Colors.white, 0.16)!, base],
          ),
          boxShadow: strong
              ? [
                  BoxShadow(
                    color: tone.glow,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          body.shortName,
          textScaler: TextScaler.noScaling,
          style: _strong(context, strong ? tone.onMark : tone.ink, size * 0.35),
        ),
      ),
    );
  }
}

/// An opened ancestor: one compact row under its own parent. Selecting it
/// lists its sub-periods again, so the tree doubles as the breadcrumb trail.
class _DashaPathNode extends StatefulWidget {
  const _DashaPathNode({
    required this.index,
    required this.period,
    required this.input,
    required this.at,
    required this.onOpen,
  });

  final int index;
  final DashaPeriod period;
  final AstrologyInput input;
  final DateTime at;
  final VoidCallback onOpen;

  static const _padding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  static const _badge = 28.0;

  static double _lead(TextScaler scaler) => math.max(_badge, _line(scaler, 14));

  /// Where the tree's elbow meets this card: its badge's center.
  static double anchor(TextScaler scaler) => _padding.top + _lead(scaler) / 2;

  @override
  State<_DashaPathNode> createState() => _DashaPathNodeState();
}

class _DashaPathNodeState extends State<_DashaPathNode> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final period = widget.period;
    final index = widget.index;
    final tone = palette.planetTone(period.lord);
    final current = period.contains(widget.at);
    final lifted = _hovered || _focused;
    final scaler = MediaQuery.textScalerOf(context);
    final lead = _DashaPathNode._lead(scaler);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final radius = BorderRadius.circular(12);
    final name = '${period.lord.label} ${vimshottariLevelNames[period.level]}';
    final withTime = period.level >= 2;
    final dates = '${_cardDate(widget.input, period.start, time: withTime)} – '
        '${_cardDate(widget.input, period.end, time: withTime)}';
    return Semantics(
      container: true,
      button: true,
      selected: current,
      label: '$name, $dates',
      hint: 'Show its ${vimshottariLevelNames[period.level + 1]}s',
      onTap: widget.onOpen,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: motion,
        curve: Curves.easeOutCubic,
        transformAlignment: Alignment.center,
        transform: _lift(lifted ? -1 : 0, pressed: _pressed),
        decoration: _toneCard(
          palette,
          tone,
          radius: radius,
          strong: current,
          lifted: lifted,
          focusRing: _focused && _keyboardFocus,
        ),
        child: Material(
          key: ValueKey('dasha-path-card-$index'),
          type: MaterialType.transparency,
          shape: RoundedRectangleBorder(borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            child: InkWell(
              key: ValueKey('dasha-breadcrumb-$index'),
              onTap: widget.onOpen,
              onHover: (value) => setState(() => _hovered = value),
              onFocusChange: (value) => setState(() => _focused = value),
              onHighlightChanged: (value) => setState(() => _pressed = value),
              excludeFromSemantics: true,
              borderRadius: radius,
              hoverColor: tone.mark.withValues(alpha: 0),
              focusColor: tone.mark.withValues(alpha: 0.08),
              highlightColor: tone.mark.withValues(alpha: 0.06),
              splashFactory: NoSplash.splashFactory,
              child: SelectionContainer.disabled(
                child: Padding(
                  padding: _DashaPathNode._padding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: lead,
                        child: Center(
                          child: _PlanetBadge(
                            body: period.lord,
                            strong: current,
                            size: _DashaPathNode._badge,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: (lead - _line(scaler, 14)) / 2,
                          ),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                name,
                                key: ValueKey('dasha-breadcrumb-$index-title'),
                                style: _strong(context, palette.ink, 14),
                              ),
                              Text(
                                '${_span(period, widget.input.dashaYearDays)} · '
                                '$dates',
                                key: ValueKey('dasha-breadcrumb-$index-dates'),
                                style: _style(context, palette.muted, 12),
                              ),
                              if (current)
                                _DashaPill(
                                  label: 'Current',
                                  tone: tone,
                                  selected: true,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: lead,
                        child: Center(
                          child: WorkspaceGlyph(
                            Icons.expand_more_rounded,
                            color: lifted ? tone.ink : palette.muted,
                            role: WorkspaceGlyphRole.preserveInk,
                          ),
                        ),
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
}

class _LordChip extends StatelessWidget {
  const _LordChip({required this.body});

  final VedicBody body;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final tone = palette.planetTone(body);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.chip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PlanetDot(body: body),
            const SizedBox(width: 6),
            Flexible(
              child: Text(body.label, style: _strong(context, tone.ink, 12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The selected period, opened in place in the tree: its status, exact
/// duration and full-precision endpoints above its own sub-periods.
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

  static const _padding = EdgeInsets.all(14);
  static const _badge = 38.0;

  static double _lead(TextScaler scaler) =>
      math.max(_badge, _line(scaler, 17) + 2 + _line(scaler, 12));

  /// Where the tree's elbow meets this card: its badge's center.
  static double anchor(TextScaler scaler) => _padding.top + _lead(scaler) / 2;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final tone = palette.planetTone(period.lord);
    final current = period.contains(at);
    final lead = _lead(MediaQuery.textScalerOf(context));
    return DecoratedBox(
      key: const ValueKey('dasha-overview'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [tone.fillStrong, tone.fill, tone.wash],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: palette.depthShadow(),
      ),
      child: Padding(
        padding: _padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: lead,
                  child: Center(
                    child: _PlanetBadge(
                      body: period.lord,
                      strong: true,
                      size: _badge,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          '${period.lord.label} ${vimshottariLevelNames[period.level]}',
                          key: const ValueKey('dasha-selected-title'),
                          style: _strong(context, palette.ink, 17),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 4),
                            child: Text(
                              _span(period, chart.input.dashaYearDays),
                              style: _style(context, palette.muted, 12),
                            ),
                          ),
                          KeyedSubtree(
                            key: const ValueKey('dasha-detail-status'),
                            child: _DashaPill(
                              id: current
                                  ? 'dasha-current-$path'
                                  : 'dasha-status-$path',
                              label: current
                                  ? 'Current'
                                  : at.isBefore(period.start)
                                      ? 'Upcoming'
                                      : 'Finished',
                              tone: tone,
                              selected: current,
                            ),
                          ),
                          _DashaPill(
                            id: 'dasha-detail-duration',
                            label:
                                _duration(period.end.difference(period.start)),
                          ),
                          if (period.contains(chart.utc))
                            const _DashaPill(label: 'Contains birth')
                          else if (!period.end.isAfter(chart.utc))
                            const _DashaPill(label: 'Entirely before birth'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (current) ...[
              const SizedBox(height: 12),
              _DashaProgress(
                id: 'dasha-detail-progress',
                period: period,
                at: at,
                color: tone.mark,
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: tone.mark.withValues(alpha: 0.2),
              ),
            ),
            _DashaDates(
              prefix: 'dasha-detail',
              input: chart.input,
              period: period,
            ),
          ],
        ),
      ),
    );
  }
}

/// Exact endpoints and their time zone: one row when there is room.
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
          const gap = 16.0;
          final start = _DashaDate(
            id: '$prefix-start',
            label: 'Start',
            value: _moment(input, period.start),
          );
          final end = _DashaDate(
            id: '$prefix-end',
            label: 'End',
            value: _moment(input, period.end),
          );
          final zone = _DashaDate(
            id: '$prefix-zone',
            label: 'Time zone',
            value: _zoneLabel(input),
            muted: true,
          );
          final column = 200 * MediaQuery.textScalerOf(context).scale(13) / 13;
          final width = constraints.maxWidth;
          if (width >= column * 3 + gap * 2) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: start),
                const SizedBox(width: gap),
                Expanded(child: end),
                const SizedBox(width: gap),
                Expanded(child: zone),
              ],
            );
          }
          final endpoints = width >= column * 2 + gap
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: start),
                    const SizedBox(width: gap),
                    Expanded(child: end),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [start, const SizedBox(height: 12), end],
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [endpoints, const SizedBox(height: 12), zone],
          );
        },
      );
}

class _DashaDate extends StatelessWidget {
  const _DashaDate({
    required this.id,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String id;
  final String label;
  final String value;
  final bool muted;

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
        const SizedBox(height: 2),
        Text(
          value,
          key: ValueKey(id),
          style: _style(context, muted ? palette.muted : palette.ink, 13),
        ),
      ],
    );
  }
}

class _DashaDetails extends StatelessWidget {
  const _DashaDetails({
    required this.chart,
    required this.first,
    required this.at,
  });

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
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
              'Reading date: ${_moment(chart.input, at)}',
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
          color: AstrologyPalette.of(context).planetTone(body).mark,
          shape: BoxShape.circle,
        ),
        child: const SizedBox(width: 7, height: 7),
      );
}

class _DashaPill extends StatelessWidget {
  const _DashaPill({
    this.id,
    required this.label,
    this.selected = false,
    this.tone,
  });

  final String? id;
  final String label;
  final bool selected;

  /// Colors a selected pill, e.g. in the period lord's tone.
  final AstrologyTone? tone;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final tone = this.tone;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? tone?.chip ?? palette.selection
            : palette.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          label,
          key: id == null ? null : ValueKey(id!),
          style: selected
              ? _strong(context, tone?.ink ?? palette.ink, 11)
              : _style(context, palette.ink, 11),
        ),
      ),
    );
  }
}

/// Whether focus is being moved with the keyboard, which earns a focus ring.
bool get _keyboardFocus =>
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

/// A card's hover lift, settling slightly while it is pressed.
Matrix4 _lift(double dy, {required bool pressed}) {
  final scale = pressed ? 0.99 : 1.0;
  return Matrix4.translationValues(0, dy, 0)..scale(scale, scale, 1.0);
}

/// A lord's card: a soft tone falling away from the badge corner and a
/// seated, layered shadow, with no outline. Only the running row glows.
BoxDecoration _toneCard(
  AstrologyPalette palette,
  AstrologyTone tone, {
  required BorderRadius radius,
  bool strong = false,
  bool lifted = false,
  bool glow = false,
  bool focusRing = false,
}) =>
    BoxDecoration(
      borderRadius: radius,
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [
          strong || lifted ? tone.fillStrong : tone.fill,
          strong ? tone.fill : tone.wash,
        ],
      ),
      boxShadow: [
        if (focusRing)
          BoxShadow(color: tone.mark.withValues(alpha: 0.5), spreadRadius: 2),
        ...palette.depthShadow(lifted: lifted),
        if (glow)
          BoxShadow(
            color: tone.glow,
            blurRadius: lifted ? 24 : 18,
            spreadRadius: -8,
            offset: Offset(0, lifted ? 12 : 9),
          ),
      ],
    );

class _DashaAction extends StatelessWidget {
  const _DashaAction({
    required this.id,
    required this.label,
    required this.onPressed,
    this.icon,
    this.focusNode,
    this.selected = false,
  });

  final String id;
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final text = Text(label);
    final ink = selected ? palette.accent : palette.ink;
    return Semantics(
      selected: selected,
      child: TextButton(
        key: ValueKey(id),
        focusNode: focusNode,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: selected ? palette.selection : palette.control,
          textStyle: _style(context, ink, 13),
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
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
                  WorkspaceGlyph(icon!, size: 16, color: ink),
                  const SizedBox(width: 6),
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

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "12 Mar 2004", or "12 Mar 2004 · 14:05" for periods short enough for the
/// hour to matter, in the chart's own clock. The overview keeps full precision.
String _cardDate(AstrologyInput input, DateTime utc, {required bool time}) {
  final local = AstrologyTime.localTime(input, utc);
  final date = '${local.day} ${_monthNames[local.month - 1]} '
      '${local.year.toString().padLeft(4, '0')}';
  return time ? '$date · ${_two(local.hour)}:${_two(local.minute)}' : date;
}

/// The two largest whole units of a period, in dasha years of this chart's
/// convention: "20 years", "1 year 8 months", "5 days 11 hours".
String _span(DashaPeriod period, double yearDays) {
  final micros = period.end.difference(period.start).inMicroseconds;
  final month = yearDays * Duration.microsecondsPerDay / 12;
  // Endpoints are rounded to microseconds: never lose a whole unit to that.
  final months = (micros / month + 1e-6).floor();
  final rest = ((micros - months * month) / Duration.microsecondsPerMinute)
      .round()
      .clamp(0, 1 << 40);
  final parts = [
    (months ~/ 12, 'year'),
    (months % 12, 'month'),
    (rest ~/ (24 * 60), 'day'),
    (rest % (24 * 60) ~/ 60, 'hour'),
    (rest % 60, 'minute'),
  ].where((part) => part.$1 > 0).take(2);
  if (parts.isEmpty) return 'under a minute';
  return parts
      .map((part) => '${part.$1} ${part.$2}${part.$1 == 1 ? '' : 's'}')
      .join(' ');
}

/// Preserve fractional seconds as well as historical offset seconds. Each
/// endpoint is resolved independently by the shared timezone service.
String _moment(AstrologyInput input, DateTime utc) {
  final offset = AstrologyTime.offsetAt(input, utc);
  final local = utc.toUtc().add(offset);
  final micros = local.millisecond * 1000 + local.microsecond;
  final fraction = micros == 0 ? '' : '.${micros.toString().padLeft(6, '0')}';
  final offsetSeconds = offset.inSeconds.abs() % 60;
  return '${local.year.toString().padLeft(4, '0')}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}$fraction '
      'UTC${AstrologyTime.offsetLabel(offset)}'
      '${offsetSeconds == 0 ? '' : ':${_two(offsetSeconds)}'}';
}

/// The share of [period] already elapsed at [at].
double _elapsed(DashaPeriod period, DateTime at) {
  final total = period.end.difference(period.start).inMicroseconds;
  if (total <= 0) return 0;
  return (at.difference(period.start).inMicroseconds / total).clamp(0.0, 1.0);
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

const _lineHeight = 1.45;

/// One line of [_style] text at [size], as laid out under [scaler]. Tree
/// elbows use it to meet each card at its badge whatever the text scale.
double _line(TextScaler scaler, double size) =>
    scaler.scale(size) * _lineHeight;

TextStyle _style(BuildContext context, Color color, double size) {
  final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
      .merge(DefaultTextStyle.of(context).style);
  return base.copyWith(
    color: color,
    fontSize: size,
    height: _lineHeight,
    fontFeatures: [
      ...?base.fontFeatures,
      const ui.FontFeature.tabularFigures(),
    ],
  );
}

/// [_style] at semibold. The bundled variable faces need the weight axis as
/// well as the weight; other inherited axes are kept.
TextStyle _strong(BuildContext context, Color color, double size) {
  final base = _style(context, color, size);
  return base.copyWith(
    fontWeight: FontWeight.w600,
    fontVariations: [
      for (final variation in base.fontVariations ?? const [])
        if (variation.axis != 'wght') variation,
      const ui.FontVariation('wght', 600),
    ],
  );
}
