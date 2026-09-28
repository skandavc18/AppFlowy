import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'contextual_find.dart';
import 'find_replace_bar.dart';
import 'surface_find_highlight.dart';
import 'text_find.dart';

export 'surface_find_highlight.dart';
export 'text_find.dart' show FindOptions;

/// One explicitly indexed plain-text field, never a serialized configuration.
@immutable
class SurfaceFindEntry {
  const SurfaceFindEntry(this.id, this.text, {this.replaceable = false});

  final Object id;
  final String text;
  final bool replaceable;
}

@immutable
class SurfaceFindMatch {
  const SurfaceFindMatch(this.entry, this.range);

  final SurfaceFindEntry entry;
  final RegExpMatch range;
  Object get id => entry.id;
}

/// A compare-and-set request. A model must check [before] AND current access
/// again inside its normal edit transaction before accepting [after].
@immutable
class SurfaceFindReplacement {
  const SurfaceFindReplacement(this.id, this.before, this.after);

  final Object id;
  final String before;
  final String after;
}

List<SurfaceFindMatch> searchSurfaceEntries(
  Iterable<SurfaceFindEntry> entries,
  String query,
  FindOptions options,
) {
  final RegExp? pattern;
  try {
    pattern = buildFindPattern(query, options);
  } on FormatException {
    return const [];
  }
  if (pattern == null) return const [];
  return [
    for (final entry in entries)
      for (final range in matchesOfPattern(entry.text, pattern))
        SurfaceFindMatch(entry, range),
  ];
}

/// Search state over an existing surface's model. It performs no I/O and owns
/// neither the model nor its undo history. Hosts call [refresh] on model updates.
class SurfaceFindController extends ChangeNotifier {
  SurfaceFindController({
    required this.search,
    this.canReplace,
    this.applyReplacements,
  });

  final List<SurfaceFindMatch> Function(String, FindOptions) search;
  final bool Function()? canReplace;
  final void Function(List<SurfaceFindReplacement>)? applyReplacements;

  final queryController = TextEditingController();
  final replacementController = TextEditingController();
  final Map<Object, Set<_SurfaceFindTargetState>> _targets = {};
  FindOptions _options = const FindOptions();
  List<SurfaceFindMatch> _matches = const [];
  final _matchIds = <Object>{};
  List<int> _occurrences = const [];

  void _indexMatches() {
    _matchIds.clear();
    final counts = <Object, int>{};
    _occurrences = [
      for (final match in _matches)
        counts.update(match.id, (count) => count + 1, ifAbsent: () => 0),
    ];
    _matchIds.addAll(counts.keys);
  }

  int _index = 0;
  bool _open = false;
  bool _showReplace = false;
  bool _disposed = false;
  int _opening = 0;
  int _navigation = 0;

  String get query => queryController.text;
  FindOptions get options => _options;
  List<SurfaceFindMatch> get matches => _matches;
  SurfaceFindMatch? get current => _matches.isEmpty ? null : _matches[_index];
  int get currentIndex => _matches.isEmpty ? -1 : _index;
  bool get isOpen => _open;
  bool get showReplace => _showReplace && supportsReplace;
  bool get supportsReplace =>
      applyReplacements != null && (canReplace?.call() ?? false);
  bool get queryInvalid => !isFindQueryValid(query, options);

  void open({bool replace = false}) {
    if (_disposed) return;
    _open = true;
    _showReplace = replace && supportsReplace;
    _opening++;
    refresh();
  }

  void close() {
    if (_disposed) return;
    _open = false;
    _showReplace = false;
    _matches = const [];
    _indexMatches();
    _index = 0;
    _navigation++;
    // Keep the query as a useful draft, but never leave highlights when closed.
    notifyListeners();
  }

  void setQuery(String value) {
    if (_disposed) return;
    if (query != value) queryController.text = value;
    _recompute(preserve: false);
  }

  void setOptions(FindOptions value) {
    if (_disposed || _options == value) return;
    _options = value;
    _recompute(preserve: false);
  }

  void toggleReplace() {
    if (!supportsReplace) return;
    _showReplace = !_showReplace;
    notifyListeners();
  }

  void refresh() {
    if (!_disposed && _open) _recompute(preserve: true);
  }

  /// Revoke owned data synchronously; the owner coalesces its next publication.
  /// Unlike refresh this never re-enters other delegates during revocation.
  void discardMatchesWhere(bool Function(SurfaceFindMatch) test) {
    if (_disposed || _matches.isEmpty) return;
    final previous = current;
    final retained = _matches.where((match) => !test(match)).toList();
    if (retained.length == _matches.length) return;
    _matches = List.unmodifiable(retained);
    _indexMatches();
    final same = retained.indexOf(previous!);
    _index = same >= 0 ? same : 0;
    if (same < 0) _navigation++;
  }

  void _recompute({required bool preserve}) {
    final previous = current;
    _matches = _open && !queryInvalid
        ? List.unmodifiable(search(query, options))
        : const [];
    _indexMatches();
    final same = preserve && previous != null
        ? _matches.indexWhere(
            (hit) =>
                hit.id == previous.id &&
                hit.range.start == previous.range.start,
          )
        : -1;
    _index = same >= 0
        ? same
        : preserve && _matches.isNotEmpty
            ? _index.clamp(0, _matches.length - 1)
            : 0;
    // A streaming update to the same occurrence must not keep dragging the
    // reader back to it. Only actual navigation (or a lost hit) reveals again.
    if (!preserve || same < 0) _navigation++;
    notifyListeners();
  }

  void step(int direction) {
    if (_disposed || _matches.isEmpty) return;
    _index = (_index + direction) % _matches.length;
    _navigation++;
    notifyListeners();
  }

  void replaceCurrent() => _replace(all: false);
  void replaceAll() => _replace(all: true);

  void _replace({required bool all}) {
    if (_disposed || !_open || !supportsReplace || queryInvalid) return;
    final selected = current;
    // Re-read before computing edits: delayed buttons must never operate on
    // an old transcript, a renamed card or an access-revoked field.
    final fresh = search(query, options);
    final eligible = fresh.where(
      (hit) =>
          hit.entry.replaceable &&
          (all ||
              (selected != null &&
                  hit.id == selected.id &&
                  hit.entry.text == selected.entry.text &&
                  hit.range.start == selected.range.start &&
                  hit.range.end == selected.range.end)),
    );
    final grouped = <Object, List<SurfaceFindMatch>>{};
    for (final hit in eligible) {
      (grouped[hit.id] ??= []).add(hit);
    }
    final edits = <SurfaceFindReplacement>[];
    for (final hits in grouped.values) {
      final before = hits.first.entry.text;
      final after = replaceMatches(
        before,
        [for (final hit in hits) hit.range],
        replacementController.text,
        useRegex: options.useRegex,
      );
      if (before != after) {
        edits.add(SurfaceFindReplacement(hits.first.id, before, after));
      }
    }
    if (edits.isNotEmpty && supportsReplace) applyReplacements!(edits);
    refresh();
    if (all || selected == null || !supportsReplace) return;
    final edit = edits.where((edit) => edit.id == selected.id).firstOrNull;
    // Only advance after an accepted edit (or a deliberate no-op replacement).
    // A refused compare-and-set must not pretend that it changed the model.
    final own = _matches.where((hit) => hit.id == selected.id).firstOrNull;
    final noChange = expandReplacement(
          replacementController.text,
          selected.range,
          useRegex: options.useRegex,
        ) ==
        selected.range.group(0);
    if (edit == null && !noChange) return;
    if (edit != null && own != null && own.entry.text != edit.after) return;
    final afterOffset = selected.range.start +
        expandReplacement(
          replacementController.text,
          selected.range,
          useRegex: options.useRegex,
        ).length;
    final entryOrder = fresh.map((hit) => hit.id).toSet().toList();
    final selectedOrder = entryOrder.indexOf(selected.id);
    final next = _matches.indexWhere(
      (hit) =>
          (hit.id == selected.id && hit.range.start >= afterOffset) ||
          entryOrder.indexOf(hit.id) > selectedOrder,
    );
    if (_matches.isNotEmpty) {
      _index = next < 0 ? 0 : next;
      _navigation++;
      notifyListeners();
    }
  }

  int occurrenceFor(Object id) {
    final selected = current;
    if (selected == null || selected.id != id) return -1;
    return _occurrences[_index];
  }

  bool contains(Object id) => _matchIds.contains(id);

  _SurfaceFindTargetState? get _currentTarget {
    final targets = _targets[current?.id];
    if (targets == null) return null;
    for (final target in targets.toList().reversed) {
      if (target.mounted &&
          target._active &&
          TickerMode.of(target.context) &&
          target._render != null &&
          surfaceFindRenderAvailable(target._render!) &&
          ModalRoute.of(target.context)?.isCurrent != false) {
        return target;
      }
    }
    return null;
  }

  /// Native reveal of a registered field after a host has mounted/panned to it.
  void revealCurrentTarget() => _currentTarget?._reveal();

  Rect? get currentTargetRect {
    final render = _currentTarget?._render;
    final rect = render?.currentRect;
    return render == null || rect == null
        ? null
        : MatrixUtils.transformRect(render.getTransformTo(null), rect);
  }

  @override
  void dispose() {
    _disposed = true;
    _targets.clear();
    queryController.dispose();
    replacementController.dispose();
    super.dispose();
  }
}

/// The same bar and routing used by document/file/database Find. The content
/// is ALWAYS the first child of the same Stack, including while Find is closed.
class SurfaceFindHost extends StatefulWidget {
  const SurfaceFindHost({
    super.key,
    required this.controller,
    required this.child,
    this.onReveal,
    this.debugLabel,
    this.hintText,
    this.coverageText,
    this.findInEditable = false,
  });

  final SurfaceFindController controller;
  final Widget child;
  final FutureOr<void> Function(SurfaceFindMatch)? onReveal;
  final String? debugLabel;
  final String? hintText;
  final String? coverageText;
  final bool findInEditable;

  @override
  State<SurfaceFindHost> createState() => _SurfaceFindHostState();
}

class _SurfaceFindHostState extends State<SurfaceFindHost> {
  final _barKey = GlobalKey();
  final _surfaceKey = GlobalKey();
  final _queryFocus = FocusNode(debugLabel: 'Surface find query');
  final _replaceFocus = FocusNode(debugLabel: 'Surface replace');
  final _barFocus = FocusNode(debugLabel: 'Surface find bar');
  FocusNode? _previousFocus;
  int _opening = 0;
  int _navigation = -1;
  int _epoch = 0;
  bool _escapeUp = false;
  String _queryText = '';
  bool _barAtBottom = false;

  SurfaceFindController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _queryText = controller.query;
    controller.addListener(_changed);
    controller.queryController.addListener(_queryChanged);
  }

  void _unlisten(SurfaceFindController previous) {
    previous.removeListener(_changed);
    previous.queryController.removeListener(_queryChanged);
  }

  @override
  void didUpdateWidget(SurfaceFindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      _unlisten(oldWidget.controller);
      _epoch++;
      _opening = 0;
      _navigation = -1;
      _previousFocus = null;
      _listen();
    }
  }

  void _queryChanged() {
    if (_queryText == controller.query) return;
    _queryText = controller.query;
    controller.setQuery(_queryText);
  }

  void _changed() {
    if (!mounted) return;
    final opening = controller.isOpen && _opening != controller._opening;
    _opening = controller._opening;
    if (opening) {
      if (!_barFocus.hasFocus) {
        _previousFocus = FocusManager.instance.primaryFocus;
      }
    }
    final navigate =
        controller.isOpen && (opening || _navigation != controller._navigation);
    _navigation = controller._navigation;
    if (opening || navigate || !controller.isOpen) _epoch++;
    final epoch = _epoch;
    setState(() {});
    if (!opening && !navigate) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_live(epoch)) return;
      if (opening) {
        FocusManager.instance.applyFocusChangesIfNeeded();
        if (!_live(epoch)) return;
        final focused = FocusManager.instance.primaryFocus;
        if (focused == _previousFocus ||
            focused is FocusScopeNode ||
            _barFocus.hasFocus) {
          _queryFocus.requestFocus();
          controller.queryController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.query.length,
          );
        }
      }
      final hit = controller.current;
      if (!navigate || hit == null || !_live(epoch)) return;
      await widget.onReveal?.call(hit);
      if (!_live(epoch)) return;
      controller.revealCurrentTarget();
      await WidgetsBinding.instance.endOfFrame;
      if (!_live(epoch)) return;
      final match = controller.currentTargetRect;
      final bar = _barKey.currentContext?.findRenderObject();
      final surface = _surfaceKey.currentContext?.findRenderObject();
      if (match != null &&
          bar is RenderBox &&
          surface is RenderBox &&
          bar.hasSize &&
          surface.hasSize) {
        final current = MatrixUtils.transformRect(
          bar.getTransformTo(null),
          Offset.zero & bar.size,
        );
        if (current.overlaps(match.inflate(4))) {
          final origin = surface.localToGlobal(Offset.zero);
          final alternate = Rect.fromLTWH(
            current.left,
            _barAtBottom
                ? origin.dy + 12
                : origin.dy + surface.size.height - bar.size.height - 12,
            bar.size.width,
            bar.size.height,
          );
          if (!alternate.overlaps(match.inflate(4))) {
            setState(() => _barAtBottom = !_barAtBottom);
          }
        }
      }
    });
  }

  bool _live(int epoch) =>
      mounted &&
      epoch == _epoch &&
      controller.isOpen &&
      TickerMode.of(context) &&
      ModalRoute.of(context)?.isCurrent != false;

  void _close({bool restoreFocus = true}) {
    if (HardwareKeyboard.instance.logicalKeysPressed
        .contains(LogicalKeyboardKey.escape)) {
      // The chat page uses Escape-UP to stop streaming. Closing its Find bar
      // consumes the whole key press, not just the down handled by Shortcuts.
      _escapeUp = true;
    }
    final restore = restoreFocus && _barFocus.hasFocus;
    final previous = _previousFocus;
    _previousFocus = null;
    controller.close();
    if (restore &&
        previous?.parent != null &&
        previous!.canRequestFocus &&
        previous.context?.mounted == true &&
        ModalRoute.of(previous.context!)?.isCurrent != false) {
      previous.requestFocus();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _unlisten(controller);
    _queryFocus.dispose();
    _replaceFocus.dispose();
    _barFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SurfaceFindScope(
        controller: controller,
        child: ContextualFindRegion(
          debugLabel: widget.debugLabel,
          findOpen: controller.isOpen,
          findFocusNode: _barFocus,
          findInEditable: widget.findInEditable,
          onFind: controller.open,
          onReplace: controller.supportsReplace
              ? () => controller.open(replace: true)
              : null,
          onDismiss: () => _close(restoreFocus: false),
          child: CallbackShortcuts(
            bindings: {
              if (controller.isOpen) ...{
                const SingleActivator(LogicalKeyboardKey.escape): _close,
                const SingleActivator(LogicalKeyboardKey.f3): () =>
                    controller.step(1),
                const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
                    controller.step(-1),
              },
            },
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (_, event) {
                if (_escapeUp &&
                    event is KeyUpEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _escapeUp = false;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Stack(
                key: _surfaceKey,
                children: [
                  Positioned.fill(child: widget.child),
                  if (controller.isOpen)
                    Positioned(
                      top: _barAtBottom ? null : 12,
                      bottom: _barAtBottom ? 12 : null,
                      left: 12,
                      right: 12,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Focus(
                          focusNode: _barFocus,
                          skipTraversal: true,
                          child: Column(
                            key: _barKey,
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              FindReplaceBar(
                                findController: controller.queryController,
                                findFocusNode: _queryFocus,
                                options: controller.options,
                                onOptionsChanged: controller.setOptions,
                                matchCount: controller.matches.length,
                                currentMatch: controller.currentIndex + 1,
                                onPrevious: controller.matches.isEmpty
                                    ? null
                                    : () => controller.step(-1),
                                onNext: controller.matches.isEmpty
                                    ? null
                                    : () => controller.step(1),
                                onSubmitted: () => controller.step(
                                  HardwareKeyboard.instance.isShiftPressed
                                      ? -1
                                      : 1,
                                ),
                                onClose: _close,
                                onTapOutside: () => _close(restoreFocus: false),
                                dismissOnTapOutside: false,
                                autofocus: false,
                                queryInvalid: controller.queryInvalid,
                                hintText: widget.hintText,
                                replaceController: controller.supportsReplace
                                    ? controller.replacementController
                                    : null,
                                replaceFocusNode: _replaceFocus,
                                showReplace: controller.showReplace,
                                onToggleReplace: controller.toggleReplace,
                                onReplace:
                                    controller.current?.entry.replaceable ==
                                            true
                                        ? controller.replaceCurrent
                                        : null,
                                onReplaceAll: controller.matches
                                        .any((hit) => hit.entry.replaceable)
                                    ? controller.replaceAll
                                    : null,
                              ),
                              if (widget.coverageText != null)
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 420),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      widget.coverageText!,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class SurfaceFindScope extends InheritedNotifier<SurfaceFindController> {
  const SurfaceFindScope({
    super.key,
    required SurfaceFindController controller,
    required super.child,
  }) : super(notifier: controller);

  static SurfaceFindController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SurfaceFindScope>()?.notifier;
}

/// Register a field for exact text highlighting and native scroll reveal.
/// Always keep this wrapper mounted, even while Find is closed.
class SurfaceFindTarget extends StatefulWidget {
  const SurfaceFindTarget({
    super.key,
    required this.id,
    required this.child,
    this.includeEditable = false,
  });

  final Object id;
  final Widget child;
  final bool includeEditable;

  @override
  State<SurfaceFindTarget> createState() => _SurfaceFindTargetState();
}

class _SurfaceFindTargetState extends State<SurfaceFindTarget> {
  final _key = GlobalKey();
  SurfaceFindController? _controller;
  int _revealedNavigation = -1;
  bool _active = true;

  RenderSurfaceFindHighlight? get _render =>
      _key.currentContext?.findRenderObject() as RenderSurfaceFindHighlight?;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = SurfaceFindScope.maybeOf(context);
    if (_controller == controller) return;
    _unregister();
    _controller = controller;
    _revealedNavigation = -1;
    if (controller != null) {
      (controller._targets[widget.id] ??= <_SurfaceFindTargetState>{})
          .add(this);
    }
  }

  @override
  void didUpdateWidget(SurfaceFindTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _revealedNavigation = -1;
      _unregister(oldWidget.id);
      final controller = _controller;
      if (controller != null) {
        (controller._targets[widget.id] ??= <_SurfaceFindTargetState>{})
            .add(this);
      }
    }
  }

  @override
  void deactivate() {
    _active = false;
    _unregister();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    final controller = _controller;
    if (controller != null) {
      (controller._targets[widget.id] ??= <_SurfaceFindTargetState>{})
          .add(this);
    }
  }

  void _unregister([Object? previousId]) {
    final id = previousId ?? widget.id;
    _controller?._targets[id]?.remove(this);
    if (_controller?._targets[id]?.isEmpty == true) {
      _controller?._targets.remove(id);
    }
  }

  void _reveal() {
    final render = _render;
    if (render == null || !surfaceFindRenderAvailable(render)) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != null) {
      unawaited(
        scrollable.position.ensureVisible(
          render,
          alignment: 0.35,
        ),
      );
    }
    render.revealCurrent();
    if (render.currentRect != null) {
      _revealedNavigation = _controller?._navigation ?? -1;
    }
  }

  void _geometryChanged() {
    final controller = _controller;
    if (!mounted ||
        controller == null ||
        !controller.isOpen ||
        controller.current?.id != widget.id ||
        controller._navigation == _revealedNavigation ||
        !identical(controller._currentTarget, this) ||
        _render?.currentRect == null) return;
    // A LazyBox/stream can finish after the host's first reveal frame. Honor
    // only the still-current request; ordinary streaming must not drag back.
    _reveal();
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return SurfaceFindHighlight(
      key: _key,
      query: controller?.isOpen == true && controller!.contains(widget.id)
          ? controller.query
          : '',
      options: controller?.options ?? const FindOptions(),
      currentOccurrence: controller?.occurrenceFor(widget.id) ?? -1,
      includeEditable: widget.includeEditable,
      onGeometryChanged: _geometryChanged,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          if (_controller?.isOpen == true) _render?.contentChanged();
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
