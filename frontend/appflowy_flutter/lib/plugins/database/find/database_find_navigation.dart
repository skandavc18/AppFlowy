import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/shared/find_replace/find_highlight.dart';
import 'package:appflowy/shared/find_replace/surface_find_highlight.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'database_find_session.dart';
import 'database_find_target.dart';

export 'database_find_target.dart';

enum DatabaseFindReveal { idle, revealing, exact, cell, row, unavailable }

/// One controller per mounted host, NOT a process-wide view-ID registry.
/// A delegated tab keeps its own anchors; the outer host lends it the session.
class DatabaseFindController extends ChangeNotifier {
  DatabaseFindController({
    required this.viewId,
    required this.isActive,
    required this.ownerBounds,
  });

  final String Function() viewId;
  final bool Function() isActive;
  final Rect? Function() ownerBounds;
  Rect? Function()? _avoidBounds;
  bool Function()? _ownsFocus;
  final _anchors = <DatabaseFindTarget, Set<RenderDatabaseFindAnchor>>{};
  final _layouts = <_DatabaseFindLayoutState>{};
  Map<DatabaseFindTarget, List<DatabaseFindMatch>> _matches = const {};
  DatabaseFindSession? _session;
  List<DatabaseFindMatch>? _publishedMatches;
  DatabaseFindViewSnapshot? _publishedSnapshot;
  DatabaseFindReveal _reveal = DatabaseFindReveal.idle;
  DatabaseFindTarget? _boundaryTarget;
  Rect? _currentBounds;
  String? _message;
  int _revision = 0;
  int _watchRevision = 0;
  bool _disposed = false;
  bool _notifyQueued = false;
  bool _invalidateQueued = false;

  DatabaseFindReveal get reveal => _reveal;
  String? get message => _message;
  Rect? get currentBounds => _currentBounds;
  bool get isOpen => _session != null;
  bool get ownsFocus => isOpen && (_ownsFocus?.call() ?? false);

  void navigate({bool forward = true}) {
    if (!_disposed && isActive()) _session?.navigate(forward: forward);
  }

  _DatabaseFindLayoutState? get _layout {
    for (final layout in _layouts.toList().reversed) {
      if (layout.viewId == viewId() && layout.isActive) return layout;
    }
    return null;
  }

  DatabaseFindViewSnapshot? snapshot() => _layout?.snapshot();

  void bind(
    DatabaseFindSession? session, {
    Rect? Function()? avoidBounds,
    bool Function()? ownsFocus,
  }) {
    if (_disposed) return;
    _session?.removeListener(_sessionChanged);
    _session = session;
    _publishedMatches = null;
    _publishedSnapshot = null;
    _avoidBounds = avoidBounds;
    _ownsFocus = ownsFocus;
    _session?.addListener(_sessionChanged);
    _sessionChanged();
    final watch = ++_watchRevision;
    if (session != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _watch(watch));
    }
  }

  void _sessionChanged() {
    if (_disposed) return;
    final revision = ++_revision;
    _boundaryTarget = null;
    _currentBounds = null;
    _message = null;
    final session = _session;
    final current = session?.current;
    if (current != null &&
        identical(_publishedMatches, session!.matches) &&
        _publishedSnapshot != snapshot()) {
      layoutChanged();
      return;
    }
    _publishedMatches = session?.matches;
    _publishedSnapshot = session == null ? null : snapshot();
    final matches = <DatabaseFindTarget, List<DatabaseFindMatch>>{};
    if (session != null && session.isOwnerActive()) {
      for (final match in session.matches) {
        final target = match.targetIn(session.viewId);
        if (target != null) (matches[target] ??= []).add(match);
      }
    }
    _matches = matches;
    _reveal = current == null
        ? DatabaseFindReveal.idle
        : DatabaseFindReveal.revealing;
    _repaint();
    _notify();
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && revision == _revision) {
          unawaited(_revealCurrent(revision, current));
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  /// Invalidate immediately, even if a reorder/access rebuild is in progress.
  /// Publication is deferred in that case; old paint/scroll work is not.
  void layoutChanged() {
    if (_disposed || _session == null) return;
    ++_revision;
    _matches = const {};
    _boundaryTarget = null;
    _currentBounds = null;
    _reveal = DatabaseFindReveal.idle;
    _message = null;
    _repaint();
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_invalidateQueued) return;
      _invalidateQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _invalidateQueued = false;
        if (!_disposed) _session?.invalidate();
      });
    } else {
      _session?.invalidate();
    }
  }

  Iterable<RenderDatabaseFindAnchor> anchors(DatabaseFindTarget target) =>
      (_anchors[target] ?? const <RenderDatabaseFindAnchor>{})
          .where((anchor) => anchor.isOnstage);

  /// Laid-out anchors can be scrolled into view even when their sliver has
  /// zero paint extent. Kept-alive rows, hidden faces and inactive views do
  /// not have usable layout geometry and must not participate in a seek.
  Iterable<RenderDatabaseFindAnchor> materializedAnchors(
    DatabaseFindTarget target,
  ) =>
      (_anchors[target] ?? const <RenderDatabaseFindAnchor>{})
          .where((anchor) => anchor.isMaterialized);

  Iterable<RenderDatabaseFindAnchor> get rows => _anchors.entries
      .where((entry) => entry.key.viewId == viewId() && entry.key.isRow)
      .expand((entry) => entry.value)
      .where((anchor) => anchor.isOnstage);

  Iterable<RenderDatabaseFindAnchor> get materializedRows => _anchors.entries
      .where((entry) => entry.key.viewId == viewId() && entry.key.isRow)
      .expand((entry) => entry.value)
      .where((anchor) => anchor.isMaterialized);

  List<DatabaseFindMatch> matchesFor(DatabaseFindTarget target) {
    final matches = _matches[target];
    if (matches == null ||
        _disposed ||
        !isActive() ||
        !(_session?.isOwnerActive() ?? false)) {
      return const [];
    }
    return matches;
  }

  /// Measured, fully visible boxes, not a row-offset estimate. Recomputed so a
  /// subsequent manual scroll/draft change cannot leave a stale success claim.
  List<Rect> get visibleMatchRects {
    final session = _session;
    final current = session?.current;
    if (session == null || current == null || !session.isOwnerActive()) {
      return const [];
    }
    final target = current.targetIn(session.viewId);
    if (target == null) return const [];
    for (final anchor in anchors(target)) {
      final geometry = anchor.measure(current);
      if (_fullyVisible(geometry)) {
        return geometry.boxes.map((box) => box.globalRect).toList();
      }
    }
    return const [];
  }

  bool _fullyVisible(DatabaseFindGeometry geometry) =>
      geometry.complete &&
      geometry.boxes.isNotEmpty &&
      geometry.boxes.every((box) {
        final actual = box.globalRect;
        final clipped = databaseFindVisibleRect(box.render, box.rect);
        final owner = ownerBounds();
        final avoid = _avoidBounds?.call();
        return clipped != null &&
            owner != null &&
            _contains(clipped, actual) &&
            _contains(owner, actual) &&
            !(avoid?.overlaps(actual) ?? false);
      });

  Future<void> _revealCurrent(int revision, DatabaseFindMatch match) async {
    final session = _session;
    if (session == null) return;
    final target = match.targetIn(session.viewId);
    if (target == null) {
      _finish(
        DatabaseFindReveal.unavailable,
        'This result has no database target.',
      );
      return;
    }
    final layout = _layout;
    final before = snapshot();
    final request = DatabaseFindRequest._(
      this,
      match,
      target,
      () =>
          !_disposed &&
          revision == _revision &&
          identical(_session, session) &&
          identical(session.current, match) &&
          identical(layout, _layout) &&
          before == snapshot() &&
          isActive() &&
          session.isOwnerActive(),
    );
    if (!request.isCurrent) return;
    if (before != null && !before.contains(target)) {
      _finish(
        DatabaseFindReveal.unavailable,
        'This row or column is not visible in the current view. Filters are unchanged.',
      );
      return;
    }
    try {
      var limitation = await layout?.materialize(request);
      if (!request.isCurrent) return;
      RenderDatabaseFindAnchor? boundary;
      // Materialization and a cell's asynchronous renderer are separate. Never
      // declare success just because a scroll controller accepted an offset.
      for (var frame = 0; frame < 16 && request.isCurrent; frame++) {
        // A row placeholder can be laid out before its cells arrive. Wrapped
        // siblings may then grow and evict that row on the next frame. Waiting
        // for its renderer alone cannot recover: reacquire the lost boundary
        // through the same layout and request, with fresh seek measurements.
        if (boundary != null && !boundary.isMaterialized) {
          final retryLimitation = await layout?.materialize(request);
          if (!request.isCurrent) return;
          limitation = retryLimitation ?? limitation;
        }
        final exact = materializedAnchors(target).toList();
        boundary = exact.isEmpty ? null : exact.first;
        if (boundary != null) {
          var geometry = boundary.measure(match);
          for (final box in geometry.boxes) {
            if (!request.isCurrent) return;
            box.revealInsideEditable();
          }
          geometry = boundary.measure(match);
          if (geometry.boxes.isNotEmpty) {
            final rect = geometry.boxes
                .map((box) => box.globalRect)
                .reduce((a, b) => a.expandToInclude(b));
            _setBounds(rect);
            for (final box in geometry.boxes) {
              if (!request.isCurrent) return;
              box.render.showOnScreen(rect: box.rect);
            }
            if (!await request.nextFrame()) return;
            geometry = boundary.measure(match);
            if (_fullyVisible(geometry)) {
              _setBounds(
                geometry.boxes
                    .map((box) => box.globalRect)
                    .reduce((a, b) => a.expandToInclude(b)),
              );
              _finish(
                DatabaseFindReveal.exact,
                'Matched text is visible in this view.',
              );
              return;
            }
          } else {
            boundary.showOnScreen();
          }
        } else if (target.rowId != null) {
          final rowTarget = DatabaseFindTarget.row(target.viewId, target.rowId);
          final rowAnchors = materializedAnchors(rowTarget).toList();
          if (rowAnchors.isNotEmpty) {
            boundary = rowAnchors.first;
            boundary.showOnScreen();
          }
        }
        if (!await request.nextFrame()) return;
      }
      if (!request.isCurrent) return;
      final rect = boundary == null
          ? null
          : databaseFindVisibleRect(boundary, Offset.zero & boundary.size);
      if (rect == null || rect.isEmpty) {
        _finish(
          DatabaseFindReveal.unavailable,
          limitation ??
              'The target is not rendered in this layout. No view, filter, or column visibility was changed.',
        );
      } else {
        _boundaryTarget = boundary!.target;
        _setBounds(rect);
        final isRow = boundary.target.isRow;
        _finish(
          isRow ? DatabaseFindReveal.row : DatabaseFindReveal.cell,
          limitation ??
              (isRow
                  ? 'Row/card reached. This layout does not display the matched property.'
                  : 'Cell reached, but the exact saved text is clipped, formatted differently, or has an unsaved edit. The cell was not changed.'),
        );
      }
    } on Object {
      if (request.isCurrent) {
        _finish(
          DatabaseFindReveal.unavailable,
          'The target could not be revealed in this layout. No values were changed.',
        );
      }
    } finally {
      if (!_disposed && revision == _revision && before != snapshot()) {
        layoutChanged();
      }
    }
  }

  void _setBounds(Rect bounds) {
    if (bounds == _currentBounds) return;
    _currentBounds = bounds;
    _notify();
  }

  void _finish(DatabaseFindReveal reveal, String message) {
    _reveal = reveal;
    _message = message;
    _repaint();
    _notify();
  }

  void _register(RenderDatabaseFindAnchor anchor) {
    (_anchors[anchor.target] ??= {}).add(anchor);
  }

  void _unregister(RenderDatabaseFindAnchor anchor) {
    final values = _anchors[anchor.target];
    values?.remove(anchor);
    if (values?.isEmpty ?? false) _anchors.remove(anchor.target);
  }

  void _repaint() {
    for (final anchor in _anchors.values.expand((value) => value)) {
      anchor.markNeedsPaint();
    }
  }

  // Observe existing frames only. A native EditableText owns repaint
  // boundaries: its internal scroll/draft can change without repainting our
  // parent. Invalidate only changed geometry; never create an idle ticker.
  void _watch(int watch) {
    if (_disposed || watch != _watchRevision || _session == null) return;
    if (_session!.current != null && _publishedSnapshot != snapshot()) {
      layoutChanged();
    }
    for (final entry in _anchors.entries) {
      if (!_matches.containsKey(entry.key)) continue;
      for (final anchor in entry.value.toList()) {
        anchor.refreshGeometry();
      }
    }
    if (_reveal == DatabaseFindReveal.exact && visibleMatchRects.isEmpty) {
      _finish(
        DatabaseFindReveal.unavailable,
        'The matched text is no longer fully visible. Next/Previous reveals it again.',
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _watch(watch));
  }

  void _notify() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
    } else if (!_notifyQueued) {
      _notifyQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notifyQueued = false;
        if (!_disposed) notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_sessionChanged);
    _session = null;
    _disposed = true;
    ++_revision;
    ++_watchRevision;
    _matches = const {};
    _anchors.clear();
    _layouts.clear();
    super.dispose();
  }
}

/// Every await and every scroll in a delegate must check this request again.
class DatabaseFindRequest {
  DatabaseFindRequest._(
    this.controller,
    this.match,
    this.target,
    this._current,
  );

  final DatabaseFindController controller;
  final DatabaseFindMatch match;
  final DatabaseFindTarget target;
  final bool Function() _current;
  bool get isCurrent => _current();

  Future<bool> nextFrame() async {
    if (!isCurrent) return false;
    await WidgetsBinding.instance.endOfFrame;
    return isCurrent;
  }
}

class DatabaseFindScope extends InheritedWidget {
  const DatabaseFindScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final DatabaseFindController controller;

  static DatabaseFindController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DatabaseFindScope>()
      ?.controller;

  @override
  bool updateShouldNotify(DatabaseFindScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Registers a layout beneath its host. [materialize] may load a lazy row or
/// navigate a calendar date, but must never edit filters, focus, or cell data.
class DatabaseFindLayout extends StatefulWidget {
  const DatabaseFindLayout({
    super.key,
    required this.viewId,
    required this.child,
    this.snapshot,
    this.materialize,
  });

  final String viewId;
  final Widget child;
  final DatabaseFindViewSnapshot? Function()? snapshot;
  final Future<String?> Function(DatabaseFindRequest request)? materialize;

  @override
  State<DatabaseFindLayout> createState() => _DatabaseFindLayoutState();
}

class _DatabaseFindLayoutState extends State<DatabaseFindLayout> {
  DatabaseFindController? _controller;
  DatabaseFindViewSnapshot? _previous;
  bool _active = true;

  String get viewId => widget.viewId;
  bool get isActive =>
      mounted && _active && databaseFindContextIsActive(context);
  DatabaseFindViewSnapshot? snapshot() => widget.snapshot?.call();
  Future<String?> materialize(DatabaseFindRequest request) async =>
      widget.materialize == null ? null : await widget.materialize!(request);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DatabaseFindScope.maybeOf(context);
    if (!identical(_controller, next)) {
      _controller?._layouts.remove(this);
      _controller?.layoutChanged();
      _controller = next;
      _controller?._layouts.add(this);
      _controller?.layoutChanged();
    }
    _previous = snapshot();
  }

  @override
  void didUpdateWidget(DatabaseFindLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = snapshot();
    if (oldWidget.viewId != viewId || next != _previous) {
      _controller?.layoutChanged();
    }
    _previous = next;
  }

  @override
  void deactivate() {
    _active = false;
    _controller?._layouts.remove(this);
    _controller?.layoutChanged();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    _controller?._layouts.add(this);
    _controller?.layoutChanged();
  }

  @override
  void dispose() {
    _controller?._layouts.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Transparent to layout, intrinsic sizing, focus, input and semantics.
/// Attach to an actual cell/heading, never to its Find snippet or a replica.
class DatabaseFindAnchor extends SingleChildRenderObjectWidget {
  const DatabaseFindAnchor({
    super.key,
    required this.target,
    required super.child,
    this.enabled = true,
  });

  final DatabaseFindTarget target;
  final bool enabled;

  @override
  RenderDatabaseFindAnchor createRenderObject(BuildContext context) =>
      RenderDatabaseFindAnchor(
        target: target,
        controller: DatabaseFindScope.maybeOf(context),
        enabled: enabled,
        brightness: Theme.of(context).brightness,
        active: () => context.mounted && databaseFindContextIsActive(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderDatabaseFindAnchor renderObject,
  ) {
    renderObject.update(
      target: target,
      controller: DatabaseFindScope.maybeOf(context),
      enabled: enabled,
      brightness: Theme.of(context).brightness,
    );
  }
}

class RenderDatabaseFindAnchor extends RenderProxyBox {
  RenderDatabaseFindAnchor({
    required DatabaseFindTarget target,
    required DatabaseFindController? controller,
    required bool enabled,
    required Brightness brightness,
    required this.active,
  })  : _target = target,
        _controller = controller,
        _enabled = enabled,
        _brightness = brightness;

  DatabaseFindTarget _target;
  DatabaseFindController? _controller;
  bool _enabled;
  Brightness _brightness;
  final bool Function() active;
  List<Object?>? _geometryStamp;

  DatabaseFindTarget get target => _target;
  bool get _canInspect =>
      _enabled && attached && hasSize && !size.isEmpty && active();

  bool get isMaterialized =>
      _canInspect &&
      _databaseFindRenderIsAvailable(this, requireVisibleSlivers: false);

  bool get isOnstage => _canInspect && databaseFindRenderIsOnstage(this);

  void update({
    required DatabaseFindTarget target,
    required DatabaseFindController? controller,
    required bool enabled,
    required Brightness brightness,
  }) {
    if (attached) _controller?._unregister(this);
    _target = target;
    _controller = controller;
    _enabled = enabled;
    _brightness = brightness;
    if (attached) _controller?._register(this);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller?._register(this);
  }

  @override
  void detach() {
    _controller?._unregister(this);
    super.detach();
  }

  List<SurfaceFindTextRun> _textRuns() {
    if (!isOnstage || child == null) return const [];
    final excluded = <RenderObject>{};
    void boundaries(RenderObject render) {
      if (render is RenderDatabaseFindAnchor) {
        excluded.add(render);
        return;
      }
      render.visitChildren(boundaries);
    }

    boundaries(child!);
    return surfaceFindTextRuns(
      child!,
      includeEditable: true,
      excluded: excluded,
    ).where((run) => databaseFindRenderIsOnstage(run.render)).toList();
  }

  DatabaseFindGeometry measure(DatabaseFindMatch match) {
    if (!isOnstage || match.targetIn(target.viewId) != target) {
      return const DatabaseFindGeometry([], false);
    }
    final source = match.part.text;
    final runs = _textRuns();
    // An editor's draft takes precedence over sizing text/hints underneath
    // the same widget. Never mark an equal substring in a different draft.
    final editors = runs.where((run) => run.render is RenderEditable).toList();
    final exact = (editors.isEmpty ? runs : editors)
        .where((run) => run.text == source)
        .toList();
    List<SurfaceFindTextRun> mapped;
    var separatorLength = 2;
    if (exact.isNotEmpty) {
      mapped = [exact.first];
    } else if (editors.isNotEmpty) {
      return const DatabaseFindGeometry([], false);
    } else if (runs.map((run) => run.text).join() == source) {
      // Inline WidgetSpan children are part of one value. Preserve both the
      // native paragraph offset and the source offset; semantic labels and
      // placeholder code units are not saved words.
      mapped = runs;
      separatorLength = 0;
    } else {
      // Selected option/file names are decoded with this same separator.
      // Ignore non-text glyphs only when the remaining complete sequence
      // reconstructs the saved value exactly. Never search widget text.
      mapped = runs
          .where((run) => run.text.isNotEmpty && source.contains(run.text))
          .toList();
      if (mapped.map((run) => run.text).join(', ') != source) {
        return const DatabaseFindGeometry([], false);
      }
    }
    var offset = 0;
    var covered = 0;
    var complete = true;
    final boxes = <DatabaseFindRangeBox>[];
    for (final run in mapped) {
      final render = run.render;
      final text = run.text;
      final start = math.max(match.range.start, offset);
      final end = math.min(match.range.end, offset + text.length);
      if (end > start) {
        final selection = TextSelection(
          baseOffset: start - offset,
          extentOffset: end - offset,
        );
        List<TextBox> nativeBoxes(TextSelection selection) =>
            run.boxes(selection.start, selection.end);
        final native = nativeBoxes(selection);
        // A paragraph can return the visible prefix of an ellipsized range.
        // Require both boundary scalars to have real glyph boxes as well.
        var firstEnd = selection.start + 1;
        if (firstEnd < selection.end &&
            text.codeUnitAt(selection.start) >= 0xD800 &&
            text.codeUnitAt(selection.start) <= 0xDBFF) {
          firstEnd++;
        }
        var lastStart = selection.end - 1;
        if (lastStart > selection.start &&
            text.codeUnitAt(lastStart) >= 0xDC00 &&
            text.codeUnitAt(lastStart) <= 0xDFFF) {
          lastStart--;
        }
        complete = complete &&
            native.isNotEmpty &&
            nativeBoxes(
              TextSelection(
                baseOffset: selection.start,
                extentOffset: firstEnd,
              ),
            ).isNotEmpty &&
            nativeBoxes(
              TextSelection(
                baseOffset: lastStart,
                extentOffset: selection.end,
              ),
            ).isNotEmpty;
        covered += end - start;
        for (final box in native) {
          final rect = box.toRect();
          if (rect.isFinite && !rect.isEmpty) {
            boxes.add(DatabaseFindRangeBox(render, rect));
          }
        }
      }
      offset += text.length + separatorLength;
    }
    return DatabaseFindGeometry(
      boxes,
      complete && covered == match.range.end - match.range.start,
    );
  }

  void refreshGeometry() {
    final stamp = <Object?>[
      isOnstage,
      if (isOnstage)
        for (final run in _textRuns()) ...[
          run.render,
          run.text,
          run.start,
          run.render.size,
          MatrixUtils.transformRect(
            run.render.getTransformTo(null),
            run.render.paintBounds,
          ),
          if (run.render is RenderEditable)
            (run.render as RenderEditable).offset.pixels,
        ],
    ];
    if (!listEquals(stamp, _geometryStamp)) {
      _geometryStamp = stamp;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final controller = _controller;
    // The ordinary database paint path must not walk ancestors/text runs.
    if (controller == null || !controller.isOpen) return;
    final matches = controller.matchesFor(target);
    if (matches.isEmpty && controller._boundaryTarget != target) return;
    if (!isOnstage ||
        !controller.isActive() ||
        !(controller._session?.isOwnerActive() ?? false)) {
      return;
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);
    for (final match in matches) {
      final current = identical(match, controller._session?.current);
      final color = current
          ? FindHighlightColors.current(_brightness)
          : FindHighlightColors.match(_brightness);
      for (final box in measure(match).boxes) {
        final visible = databaseFindVisibleRect(box.render, box.rect);
        if (visible == null || visible.isEmpty) continue;
        final rect = Rect.fromPoints(
          globalToLocal(visible.topLeft),
          globalToLocal(visible.bottomRight),
        ).shift(offset);
        // This is a foreground wash, not a replacement text span. Keep the
        // original glyphs, selection/composing underline and native semantics.
        canvas.drawRect(
          rect,
          Paint()..color = color.withValues(alpha: color.a * 0.38),
        );
        if (current) {
          canvas.drawLine(
            rect.bottomLeft,
            rect.bottomRight,
            Paint()
              ..color = color
              ..strokeWidth = 1.5,
          );
        }
      }
    }
    if (controller._boundaryTarget == target && controller.isOpen) {
      canvas.drawRect(
        (offset & size).deflate(1),
        Paint()
          ..color = FindHighlightColors.current(_brightness)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.restore();
  }
}

class DatabaseFindGeometry {
  const DatabaseFindGeometry(this.boxes, this.complete);
  final List<DatabaseFindRangeBox> boxes;
  final bool complete;
}

class DatabaseFindRangeBox {
  const DatabaseFindRangeBox(this.render, this.rect);
  final RenderBox render;
  final Rect rect;

  Rect get globalRect =>
      MatrixUtils.transformRect(render.getTransformTo(null), rect);

  void revealInsideEditable() {
    final editable = render;
    if (editable is! RenderEditable || editable.obscureText) return;
    final horizontal = editable.maxLines == 1;
    final leading = horizontal ? rect.left : rect.top;
    final trailing = horizontal ? rect.right : rect.bottom;
    final extent = horizontal ? editable.size.width : editable.size.height;
    final delta = leading < 0
        ? leading
        : trailing > extent
            ? (trailing - leading > extent ? leading : trailing - extent)
            : 0.0;
    if (delta.abs() < 0.1) return;
    editable.offset.jumpTo(
      (editable.offset.pixels + delta)
          .clamp(0.0, editable.maxScrollExtent)
          .toDouble(),
    );
  }
}

bool _contains(Rect outer, Rect inner) =>
    outer.left <= inner.left + 0.1 &&
    outer.top <= inner.top + 0.1 &&
    outer.right >= inner.right - 0.1 &&
    outer.bottom >= inner.bottom - 0.1;

bool databaseFindContextIsActive(BuildContext context) {
  if (!context.mounted) return false;
  final routes = <ModalRoute<dynamic>>{};
  var route = ModalRoute.of(context);
  while (route != null && routes.add(route)) {
    if (!route.isCurrent) return false;
    final navigator = route.navigator;
    route = navigator != null && navigator.mounted
        ? ModalRoute.of(navigator.context)
        : null;
  }
  var active = true;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if ((widget is Offstage && widget.offstage) ||
        (widget is Visibility && !widget.visible) ||
        (widget is TickerMode && !widget.enabled)) {
      active = false;
      return false;
    }
    return true;
  });
  return active;
}

bool databaseFindRenderIsOnstage(RenderObject object) =>
    _databaseFindRenderIsAvailable(object, requireVisibleSlivers: true);

bool _databaseFindRenderIsAvailable(
  RenderObject object, {
  required bool requireVisibleSlivers,
}) {
  if (!object.attached) return false;
  RenderObject child = object;
  for (var parent = child.parent; parent != null; parent = child.parent) {
    // In particular, paintsChild rejects a sliver's keep-alive bucket: those
    // children have stale layout offsets and a zeroed paint transform.
    if (!parent.attached || !parent.paintsChild(child)) return false;
    if (parent is RenderOffstage && parent.offstage) return false;
    if (parent is RenderOpacity && parent.opacity == 0) return false;
    if (parent is RenderAnimatedOpacity && parent.opacity.value == 0) {
      return false;
    }
    if (requireVisibleSlivers &&
        parent is RenderSliver &&
        parent.geometry?.visible != true) {
      return false;
    }
    if (parent is RenderIndexedStack) {
      var displayed = parent.firstChild;
      if (parent.index == null) return false;
      for (var i = 0; i < parent.index! && displayed != null; i++) {
        displayed = parent.childAfter(displayed);
      }
      if (!identical(displayed, child)) return false;
    }
    child = parent;
  }
  return true;
}

Rect? databaseFindVisibleRect(RenderBox object, Rect rect) {
  if (!object.hasSize || !databaseFindRenderIsOnstage(object)) return null;
  // A cell must never paint through its neighbour or outside its editor.
  var bounds = MatrixUtils.transformRect(
    object.getTransformTo(null),
    rect.intersect(Offset.zero & object.size),
  );
  RenderObject child = object;
  for (var parent = child.parent; parent != null; parent = child.parent) {
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      bounds = bounds.intersect(
        MatrixUtils.transformRect(parent.getTransformTo(null), clip),
      );
    }
    if (parent is RenderDatabaseFindAnchor) {
      bounds = bounds.intersect(
        MatrixUtils.transformRect(
          parent.getTransformTo(null),
          Offset.zero & parent.size,
        ),
      );
    }
    child = parent;
  }
  return bounds.isFinite && !bounds.isEmpty ? bounds : null;
}
