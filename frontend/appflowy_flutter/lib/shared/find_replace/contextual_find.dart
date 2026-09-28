import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Marks a page whose outermost visible Find owner is the keyboard fallback.
///
/// This is a passive boundary, not an autofocus request. A workspace can keep
/// many pages mounted: current-route and painted-visibility checks still decide
/// which one is eligible. Embedded previews must not introduce another scope.
/// A secondary pane may opt out of fallback while retaining hover/focus Find.
class ContextualFindScope extends InheritedWidget {
  const ContextualFindScope({
    super.key,
    required super.child,
    this.enabled = true,
    this.findInControls = false,
  });

  final bool enabled;

  /// A full page also owns Find from its title, cover and other header fields.
  /// Opt in at the page boundary, not globally: dialogs and unrelated inputs
  /// outside this scope must keep their own shortcuts and drafts.
  final bool findInControls;

  static ContextualFindScope? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ContextualFindScope>();

  @override
  bool updateShouldNotify(ContextualFindScope oldWidget) =>
      enabled != oldWidget.enabled ||
      findInControls != oldWidget.findInControls;
}

/// Supplies live block selection to owned viewers without an editor dependency.
///
/// Keep this wrapper below the enclosing page's [ContextualFindRegion] and around
/// the interactive preview, not the page or unrelated controls. Only descendant
/// regions in that same find tree can inherit it; the page never reads down into
/// a selected child. Selection alone does not enable hidden or inactive viewers.
class ContextualFindSelection extends InheritedWidget {
  const ContextualFindSelection({
    super.key,
    required this.isSelected,
    required super.child,
  });

  /// A live, side-effect-free check, read at dispatch rather than during build.
  final bool Function() isSelected;

  /// The nearest marker below this region's find root, without subscribing to
  /// rebuilds. A marker above a root or across a route boundary is not inherited.
  static ContextualFindSelection? maybeOf(BuildContext context) {
    if (!context.mounted) return null;
    final marker = context
        .getElementForInheritedWidgetOfExactType<ContextualFindSelection>();
    final root = _regionAt(context)?._root;
    if (marker == null || root == null || !_within(marker, root.context)) {
      return null;
    }
    return marker.widget as ContextualFindSelection;
  }

  @override
  bool updateShouldNotify(ContextualFindSelection oldWidget) =>
      isSelected != oldWidget.isSelected;
}

/// Routes find to the content under the pointer, before editor key handlers.
///
/// Nested regions win over their ancestors. Without a content hover, a focused
/// viewer (including its external [findFocusNode]) wins, followed by a selected
/// embed and the last activated region. An enclosing page's focus is a fallback
/// rather than a reason to search the page instead of its selected embed.
/// Its background hover is also a fallback while a descendant owns find; a
/// content click outside that descendant invalidates the last-owner fallback.
///
/// There is one early FocusManager handler while any regions are mounted. This
/// widget never requests focus, changes selection, paints, or owns search state.
/// Ordinary editable fields, other routes, and native platform views retain
/// their keyboard handling. Only source/cell content should opt into
/// [findInEditable]; page titles, captions and unrelated query fields must not.
/// Supply [findFocusNode] to identify a search field; it need not be a descendant
/// of [child].
class ContextualFindRegion extends StatefulWidget {
  const ContextualFindRegion({
    super.key,
    required this.child,
    required this.onFind,
    this.onReplace,
    this.onDismiss,
    this.findOpen = false,
    this.findFocusNode,
    this.enabled = true,
    this.isActive,
    bool findInEditable = false,
    bool? ownsEditable,
    this.isSelected,
    this.debugLabel,
    this.useNativeFind = false,
    this.claimHoverFromControls = true,
    this.navigation = false,
  }) : findInEditable = ownsEditable ?? findInEditable;

  final Widget child;
  final VoidCallback onFind;

  /// Opens replace for this target, on Ctrl/Cmd+H or explicit dispatch.
  ///
  /// A null callback makes the target find-only. Replace is then claimed without
  /// a callback, so a PDF/image cannot accidentally replace the enclosing page.
  final VoidCallback? onReplace;

  /// Closes this find UI WITHOUT restoring its former focus.
  ///
  /// Before opening another owner, all other [findOpen] regions in the same
  /// current page/region tree are dismissed, including ones opened by a button
  /// rather than this router. Independent trees and hidden routes are untouched.
  /// The new owner's callback, not this widget, decides where focus should go.
  final VoidCallback? onDismiss;
  final bool findOpen;
  final FocusNode? findFocusNode;
  final bool enabled;

  /// Live owner/pane availability, also required by nested regions. Unlike
  /// [isSelected], false prevents hover, focus AND last-owner fallback.
  final bool Function()? isActive;

  /// Whether text inputs inside this region are its searchable content.
  ///
  /// A source/text viewer owns its EditableText. An enclosing document does
  /// not own ordinary title/caption fields. Only the nearest region decides;
  /// an unrelated field must never borrow an ancestor's find command.
  /// Opt in around the editable content, not the viewer's title/control fields.
  /// This applies to both real RenderEditable hover hits and keyboard focus;
  /// registered [findFocusNode] fields retain their owner independently.
  final bool findInEditable;

  /// Compatibility alias for the earlier ownership API. If supplied to the
  /// constructor it overrides [findInEditable]; prefer [findInEditable].
  bool get ownsEditable => findInEditable;

  /// A live, side-effect-free selection check, not a cached selection snapshot.
  /// When null, the nearest in-tree [ContextualFindSelection] supplies the check.
  /// An explicit callback returning false overrides that inherited selection.
  final bool Function()? isSelected;
  final String? debugLabel;

  /// Defers to local/native key handling, without falling back to a parent
  /// region. Useful for texture-backed webviews whose native focus is not
  /// represented by Flutter's platform-view widgets. Set this while native find
  /// owns the command; [enabled] instead disables this target entirely. Do not
  /// set this for a Flutter find bar driven by a native-to-Flutter bridge.
  final bool useNativeFind;

  /// An explicit hit on this content can own Find while a non-text navigation
  /// control still has focus. Hover does not move focus or selection. Editable
  /// fields, native viewers and modal routes still retain their own handling.
  /// Set false only for a host whose controls must retain local Find instead.
  final bool claimHoverFromControls;

  /// Sidebar/navigation Find opens workspace search. An explicit hover here
  /// may take over an open page query; independent content panes may not.
  final bool navigation;

  /// Optional entry point for a customized editor shortcut; normally unneeded.
  ///
  /// Only the nearest enclosing region and its descendants are considered (or
  /// descendants of [context] if there is no enclosing region). Returns whether
  /// the command was claimed, including a find-only target declining replace.
  /// False leaves the command to the caller's normal/local handling.
  static bool dispatch(BuildContext context, {bool replace = false}) {
    if (!context.mounted) return false;
    return _FindRouter.instance.dispatch(context: context, replace: replace);
  }

  @visibleForTesting
  static int get debugRegisteredRegionCount =>
      _FindRouter.instance.regions.length;

  @visibleForTesting
  static bool get debugHasEarlyKeyHandler =>
      _FindRouter.instance.manager != null;

  /// Counts actual early-handler invocations in debug mode, including ignored
  /// events, so tests can detect duplicate registration and removal leaks.
  @visibleForTesting
  static int get debugKeyEventCount => _FindRouter.instance.keyEventCount;

  @override
  State<ContextualFindRegion> createState() => _ContextualFindRegionState();
}

class _ContextualFindRegionState extends State<ContextualFindRegion> {
  final _surfaceKey = GlobalKey();
  late final _focusOwner = FocusNode(
    debugLabel: widget.debugLabel ?? 'Contextual find',
    canRequestFocus: false,
    skipTraversal: true,
  );
  bool _active = true;
  bool _tickerEnabled = true;
  int _viewId = 0;
  List<ModalRoute<dynamic>> _routes = [];

  ModalRoute<dynamic>? get _route => _routes.firstOrNull;
  bool get _current => _routes.every((route) => route.isCurrent);
  int get _depth => (context as Element).depth;

  _ContextualFindRegionState get _root {
    var root = this;
    var parent = context.findAncestorStateOfType<_ContextualFindRegionState>();
    while (parent != null && parent._route == _route) {
      root = parent;
      parent =
          parent.context.findAncestorStateOfType<_ContextualFindRegionState>();
    }
    return root;
  }

  Rect? get _bounds {
    if (!_active || !mounted || !_tickerEnabled || !_current) return null;
    return _visibleBounds(_surfaceKey.currentContext?.findRenderObject());
  }

  bool get _available {
    if (_bounds == null) return false;
    _ContextualFindRegionState? owner = this;
    while (owner != null && owner._route == _route) {
      if (!owner.widget.enabled || !(owner.widget.isActive?.call() ?? true)) {
        return false;
      }
      owner =
          owner.context.findAncestorStateOfType<_ContextualFindRegionState>();
    }
    return true;
  }

  bool get _hasFindFocus {
    final node = widget.findFocusNode;
    if (node == null || node.parent == null || !node.hasFocus) return false;
    final nodeContext = node.context;
    if (nodeContext == null || !nodeContext.mounted) return false;
    final route = ModalRoute.of(nodeContext);
    return (route == null || route == _route) &&
        View.maybeOf(nodeContext)?.viewId == _viewId &&
        TickerMode.of(nodeContext) &&
        _visibleBounds(nodeContext.findRenderObject()) != null;
  }

  bool get _hasContentFocus {
    if (!_focusOwner.hasFocus) return false;
    final primaryContext = FocusManager.instance.primaryFocus?.context;
    return primaryContext != null &&
        primaryContext.mounted &&
        _renderWithin(
          primaryContext.findRenderObject(),
          _surfaceKey.currentContext?.findRenderObject(),
        );
  }

  bool get _hasFocus => _hasContentFocus || _hasFindFocus;

  @override
  void initState() {
    super.initState();
    _FindRouter.instance.register(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.of(context);
    _viewId = View.of(context).viewId;
    // Check enclosing navigators too: a nested navigator's current route can
    // still be covered by a dialog in the root navigator.
    _routes = [];
    var route = ModalRoute.of(context);
    while (route != null && !_routes.contains(route)) {
      _routes.add(route);
      final navigator = route.navigator;
      route = navigator != null && navigator.mounted
          ? ModalRoute.of(navigator.context)
          : null;
    }
    if (!_tickerEnabled || !_current) _FindRouter.instance.forget(this);
  }

  @override
  void didUpdateWidget(ContextualFindRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _focusOwner.debugLabel = widget.debugLabel ?? 'Contextual find';
    if (!widget.enabled || widget.useNativeFind) {
      _FindRouter.instance.forget(this);
    }
  }

  @override
  void deactivate() {
    _active = false;
    _FindRouter.instance.unregister(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    _FindRouter.instance.register(this);
  }

  @override
  void dispose() {
    _FindRouter.instance.unregister(this);
    _focusOwner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _focusOwner,
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        child: MouseRegion(
          opaque: false,
          // Seeds a stationary cursor when a region appears beneath it. No
          // per-region hover flags, setState, focus, or selection side effects.
          onEnter: _FindRouter.instance.rememberCursor,
          child: _FindSurface(
            key: _surfaceKey,
            region: this,
            child: widget.child,
          ),
        ),
      );
}

class _FindRouter with WidgetsBindingObserver {
  static final instance = _FindRouter();

  final regions = <_ContextualFindRegionState>{};
  final _claimedKeys = <PhysicalKeyboardKey>{};
  FocusManager? manager;
  WidgetsBinding? _binding;
  PointerEvent? _cursor;
  _ContextualFindRegionState? _last;
  bool _dispatching = false;
  int keyEventCount = 0;

  void register(_ContextualFindRegionState region) {
    if (!regions.add(region) || manager != null) return;
    _binding = WidgetsBinding.instance;
    manager = FocusManager.instance;
    manager!
      ..addEarlyKeyEventHandler(_onKey)
      ..addListener(_onFocusChange);
    _binding!
      ..addObserver(this)
      ..pointerRouter.addGlobalRoute(_onPointer);
  }

  void unregister(_ContextualFindRegionState region) {
    regions.remove(region);
    forget(region);
    if (regions.isNotEmpty || manager == null) return;
    manager!
      ..removeEarlyKeyEventHandler(_onKey)
      ..removeListener(_onFocusChange);
    _binding!
      ..removeObserver(this)
      ..pointerRouter.removeGlobalRoute(_onPointer);
    manager = null;
    _binding = null;
    _cursor = null;
    _last = null;
    _claimedKeys.clear();
  }

  void forget(_ContextualFindRegionState region) {
    if (identical(_last, region)) _last = null;
  }

  void rememberCursor(PointerEvent event) {
    if (manager == null || event.kind != PointerDeviceKind.mouse) return;
    if (event is PointerRemovedEvent) {
      if (_cursor?.device == event.device) _cursor = null;
    } else {
      _cursor = event;
    }
  }

  void _onPointer(PointerEvent event) {
    rememberCursor(event);
    if (event is! PointerDownEvent && event is! PointerSignalEvent) return;
    final last = _last;
    if (last == null) return;
    final hit = _hitTest(event);
    if (!hit.path.any(
      (entry) =>
          entry.target is _RenderFindSurface &&
          identical((entry.target as _RenderFindSurface).region, last),
    )) {
      // Clicking/scrolling elsewhere invalidates fallback even if that control
      // does not request focus. Merely leaving a region does not activate it.
      _last = null;
    }
  }

  void _onFocusChange() {
    final last = _last;
    if (last != null && (!last._available || !last._hasFocus)) _last = null;
  }

  @override
  void didChangeMetrics() => _last = null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _cursor = null;
    _last = null;
    _claimedKeys.clear();
  }

  KeyEventResult _onKey(KeyEvent event) {
    assert(() {
      keyEventCount++;
      return true;
    }());
    if (event is KeyUpEvent) {
      return _claimedKeys.remove(event.physicalKey)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (_claimedKeys.contains(event.physicalKey)) {
      // Consume repeats of OUR press; otherwise a local Shortcut could open a
      // second find UI after our original KeyDown was handled.
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent || event.synthesized) {
      return KeyEventResult.ignored;
    }
    final keyboard =
        HardwareKeyboard.instance; // Read modifiers, never register.
    if (keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed == keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final replace = event.logicalKey == LogicalKeyboardKey.keyH;
    if (!replace && event.logicalKey != LogicalKeyboardKey.keyF) {
      return KeyEventResult.ignored;
    }
    if (!dispatch(replace: replace)) return KeyEventResult.ignored;
    if (manager != null) _claimedKeys.add(event.physicalKey);
    return KeyEventResult.handled;
  }

  bool dispatch({BuildContext? context, required bool replace}) {
    if (_dispatching) return true;
    final target = _resolve(context);
    if (target == null || target.widget.useNativeFind) return false;
    final callback = replace ? target.widget.onReplace : target.widget.onFind;
    // In this SDK, skipRemainingHandlers in an EARLY handler still falls
    // through to the focus tree. Claim an unsupported replace explicitly.
    if (callback == null) return true;
    _dispatching = true;
    try {
      final root = target._root;
      for (final other in regions.toList()) {
        if (other != target &&
            other._bounds != null &&
            other._viewId == target._viewId &&
            other._route == target._route &&
            (target.widget.navigation || identical(other._root, root)) &&
            other.widget.findOpen) {
          other.widget.onDismiss?.call();
        }
      }
      // A dismiss callback may synchronously navigate or remove a target.
      if (regions.contains(target) && target._available) {
        _last = target;
        callback();
      }
      return true;
    } finally {
      _dispatching = false;
    }
  }

  _ContextualFindRegionState? _resolve(BuildContext? source) {
    if (manager == null) return null;
    final lifecycle = _binding!.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return null;
    }
    final available = regions.where((region) => region._available).toList();
    if (_last != null && !available.contains(_last)) _last = null;
    if (available.isEmpty) return null;

    final primary = manager!.primaryFocus;
    final focusContext = primary?.context;
    final liveFocus = focusContext != null && focusContext.mounted;
    final queryOwner =
        _deepest(available.where((region) => region._hasFindFocus));
    final focused = _deepest(
      available.where((region) => region._hasContentFocus),
    );
    final nearestFocus = liveFocus ? _regionAt(focusContext) : null;
    var unownedEditableFocus = false;
    if (liveFocus && queryOwner == null) {
      if (_isNativeFocus(focusContext)) return null;
      if (_isEditable(focusContext) &&
          (nearestFocus == null ||
              !available.contains(nearestFocus) ||
              !nearestFocus._hasContentFocus ||
              !nearestFocus.widget.findInEditable)) {
        unownedEditableFocus = true;
      }
    }
    if (queryOwner == null &&
        nearestFocus != null &&
        available.contains(nearestFocus) &&
        !nearestFocus._hasContentFocus) {
      return null; // A portal menu retains ancestry, but renders outside content.
    }
    final unrelatedControlFocus = primary != null &&
        primary is! FocusScopeNode &&
        queryOwner == null &&
        focused == null &&
        !available
            .any((region) => region._focusOwner.ancestors.contains(primary));
    if ((queryOwner ?? focused)?.widget.useNativeFind ?? false) return null;

    final focusRoute = liveFocus ? ModalRoute.of(focusContext) : null;
    final focusView = liveFocus ? View.maybeOf(focusContext)?.viewId : null;
    final enclosing = source == null ? null : _regionAt(source);
    final scope = enclosing?.context ?? source;
    final candidates = available.where((region) {
      return (scope == null || _within(region.context, scope)) &&
          (focusView == null || region._viewId == focusView) &&
          // Navigation can live above a nested content Navigator. Its current
          // ancestor route is compatible, not an unrelated modal route.
          (focusRoute == null || region._routes.contains(focusRoute));
    }).toList();
    if (candidates.isEmpty) return null;
    if (unownedEditableFocus) {
      return _pageForControls(focusContext!, candidates);
    }

    _ContextualFindRegionState? hoveredPage;
    final cursor = _cursor;
    if (cursor != null && (focusView == null || cursor.viewId == focusView)) {
      final hit = _hitTest(cursor);
      final queryHit = available.any((region) {
        final node = region.widget.findFocusNode;
        final nodeContext = node?.context;
        return node?.parent != null &&
            nodeContext != null &&
            nodeContext.mounted &&
            _hitsContext(hit, nodeContext);
      });
      if (hit.path.any((entry) => _isNativeSurface(entry.target))) return null;
      if (!queryHit) {
        final editableHit =
            hit.path.any((entry) => entry.target is RenderEditable);
        for (final entry in hit.path) {
          final surface = entry.target;
          if (surface is _RenderFindSurface) {
            // Use hit-test order, not registration order, labels, cached enter
            // flags, or the depth of an unrelated overlapping sibling.
            final hovered = surface.region;
            if (!candidates.contains(hovered)) return null;
            if (unrelatedControlFocus &&
                !hovered.widget.claimHoverFromControls) {
              return null;
            }
            // A native owner wins even while a Flutter query has focus or the
            // native region is the root of a tree with nested Flutter content.
            if (hovered.widget.useNativeFind) return null;
            if (editableHit && !hovered.widget.findInEditable) {
              return candidates.contains(queryOwner)
                  ? queryOwner
                  : _pageForControls(hovered.context, candidates);
            }
            if (hovered.widget.navigation) return hovered;
            if (queryOwner != null &&
                (!identical(hovered._root, queryOwner._root) ||
                    _within(queryOwner.context, hovered.context))) {
              // Only explicit nested content in this page can take an open
              // query away from its owner, not page background/another pane.
              return candidates.contains(queryOwner) ? queryOwner : null;
            }
            if (identical(hovered, hovered._root) &&
                available.any(
                  (region) =>
                      region != hovered && identical(region._root, hovered),
                )) {
              hoveredPage = hovered;
              break;
            }
            return hovered;
          }
        }
        if (editableHit) {
          return candidates.contains(queryOwner) ? queryOwner : null;
        }
        if (hoveredPage == null &&
            candidates.any(
              (region) =>
                  region._viewId == cursor.viewId &&
                  region._bounds!.contains(cursor.position),
            )) {
          return null; // An overlay/absorber, not the content, was hit.
        }
      }
    }

    if (unrelatedControlFocus) {
      return hoveredPage ?? _pageFallback(candidates);
    }
    if (queryOwner != null) {
      return candidates.contains(queryOwner) ? queryOwner : null;
    }
    // Offstage/disabled descendants can retain focus. Do not turn that stale
    // focus into an enclosing page's find command.
    if (nearestFocus != null && !available.contains(nearestFocus)) return null;
    if (focused != null && focused != focused._root) {
      return candidates.contains(focused) ? focused : null;
    }

    final anchor = focused?._root ?? _last?._root ?? enclosing?._root;
    final family = candidates
        .where(
          (region) => anchor == null || identical(region._root, anchor),
        )
        .toList();
    // With no focus/activation anchor, do not pick a selection from an arbitrary
    // independent editor just because it happened to register first.
    final roots = family.map((region) => region._root).toSet();
    if (roots.length == 1) {
      final selected = _deepest(
        family.where((region) {
          final isSelected = region.widget.isSelected ??
              ContextualFindSelection.maybeOf(region.context)?.isSelected;
          return isSelected?.call() ?? false;
        }),
      );
      if (selected != null) return selected;
    }
    if (_last != null && family.contains(_last)) return _last;
    return hoveredPage ??
        (candidates.contains(focused) ? focused : null) ??
        _pageFallback(candidates);
  }
}

_ContextualFindRegionState? _pageForControls(
  BuildContext context,
  List<_ContextualFindRegionState> candidates,
) {
  final element =
      context.getElementForInheritedWidgetOfExactType<ContextualFindScope>();
  final scope = element?.widget as ContextualFindScope?;
  if (scope == null ||
      !scope.findInControls ||
      !_renderWithin(context.findRenderObject(), element!.findRenderObject())) {
    return null;
  }
  final family = candidates
      .where(
        (region) => identical(ContextualFindScope._of(region.context), scope),
      )
      .toList();
  // An explicitly focused secondary pane can find from its header while it
  // remains ineligible as the primary page's no-focus fallback.
  final roots = family
      .where(
        (region) => !family.any(
          (other) => other != region && _within(region.context, other.context),
        ),
      )
      .toList();
  return roots.length == 1 ? roots.single : null;
}

_ContextualFindRegionState? _pageFallback(
  List<_ContextualFindRegionState> candidates,
) {
  final scoped = candidates
      .where(
        (region) => ContextualFindScope._of(region.context)?.enabled == true,
      )
      .toList();
  if (scoped.isEmpty) return null;
  final scopes =
      scoped.map((region) => ContextualFindScope._of(region.context)).toSet();
  // Never use registration order to choose between independent visible panes.
  if (scopes.length != 1) return null;
  final roots = scoped
      .where(
        (region) => !scoped.any(
          (other) => other != region && _within(region.context, other.context),
        ),
      )
      .toList();
  // The page owns the default, not whichever nested preview mounted last.
  return roots.length == 1 ? roots.single : null;
}

_ContextualFindRegionState? _regionAt(BuildContext context) {
  if (context is StatefulElement &&
      context.state is _ContextualFindRegionState) {
    return context.state as _ContextualFindRegionState;
  }
  return context.findAncestorStateOfType<_ContextualFindRegionState>();
}

bool _within(BuildContext child, BuildContext ancestor) {
  if (identical(child, ancestor)) return true;
  var found = false;
  child.visitAncestorElements((element) {
    found = identical(element, ancestor);
    return !found;
  });
  return found;
}

_ContextualFindRegionState? _deepest(
  Iterable<_ContextualFindRegionState> regions,
) {
  _ContextualFindRegionState? result;
  for (final region in regions) {
    if (result == null || region._depth > result._depth) result = region;
  }
  return result;
}

HitTestResult _hitTest(PointerEvent event) {
  final result = HitTestResult();
  RendererBinding.instance.hitTestInView(result, event.position, event.viewId);
  // The inactive spreadsheet's scroll gate still allows ordinary pointers,
  // but wraps their targets to suppress wheel/pan input. Preserve content
  // identity for this read-only lookup; NEVER dispatch this inspection result.
  final content = HitTestResult();
  for (final entry in result.path) {
    content.add(HitTestEntry(ScrollGestureGate.originalTarget(entry.target)));
  }
  return content;
}

bool _hitsContext(HitTestResult hit, BuildContext context) {
  final render = context.findRenderObject();
  if (_visibleBounds(render) == null) return false;
  return hit.path.any(
    (entry) =>
        entry.target is RenderObject &&
        _renderWithin(entry.target as RenderObject, render),
  );
}

bool _renderWithin(RenderObject? child, RenderObject? ancestor) {
  if (ancestor == null || !ancestor.attached) return false;
  for (var current = child; current != null; current = current.parent) {
    if (identical(current, ancestor)) return true;
  }
  return false;
}

bool _isEditable(BuildContext context) =>
    context.widget is EditableText ||
    context.findAncestorWidgetOfExactType<EditableText>() != null;

bool _isNativeSurface(Object? object) =>
    object is PlatformViewRenderBox ||
    object is RenderUiKitView ||
    object is RenderAppKitView;

bool _isNativeFocus(BuildContext context) {
  if (context.findAncestorWidgetOfExactType<PlatformViewLink>() != null ||
      context.findAncestorWidgetOfExactType<HtmlElementView>() != null ||
      context.findAncestorWidgetOfExactType<AndroidView>() != null ||
      context.findAncestorWidgetOfExactType<UiKitView>() != null ||
      context.findAncestorWidgetOfExactType<AppKitView>() != null) {
    return true;
  }
  // A leaf Focus can directly wrap a native surface through several proxies.
  // Never scan a whole editor's descendants: it may merely contain a webview.
  var render = context.findRenderObject();
  while (render is RenderProxyBox) {
    render = render.child;
  }
  return _isNativeSurface(render);
}

/// Current painted geometry, including ancestor clips and retained hidden tabs.
Rect? _visibleBounds(RenderObject? object) {
  if (object is! RenderBox ||
      !object.attached ||
      !object.hasSize ||
      object.size.isEmpty ||
      !object.size.isFinite) {
    return null;
  }
  var bounds = MatrixUtils.transformRect(
    object.getTransformTo(null),
    Offset.zero & object.size,
  );
  if (!bounds.isFinite || bounds.isEmpty) return null;
  RenderObject child = object;
  for (var parent = child.parent; parent != null; parent = child.parent) {
    if (!parent.attached || !parent.paintsChild(child)) return null;
    if (parent is RenderSliver && parent.geometry?.visible != true) return null;
    // This SDK's RenderIndexedStack does not override paintsChild.
    if (parent is RenderIndexedStack) {
      if (parent.index == null) return null;
      var displayed = parent.firstChild;
      for (var index = 0; index < parent.index! && displayed != null; index++) {
        displayed = parent.childAfter(displayed);
      }
      if (!identical(displayed, child)) return null;
    }
    final clip = parent is RenderClipRect && parent.clipBehavior != Clip.none
        ? parent.clipper?.getClip(parent.size) ?? Offset.zero & parent.size
        : parent.describeApproximatePaintClip(child);
    if (clip != null) {
      bounds = bounds.intersect(
        MatrixUtils.transformRect(parent.getTransformTo(null), clip),
      );
    }
    if (parent is RenderView) {
      bounds = bounds.intersect(Offset.zero & parent.size);
    }
    if (!bounds.isFinite || bounds.isEmpty) return null;
    child = parent;
  }
  return bounds;
}

class _FindSurface extends SingleChildRenderObjectWidget {
  const _FindSurface({super.key, required this.region, required super.child});

  final _ContextualFindRegionState region;

  @override
  _RenderFindSurface createRenderObject(BuildContext context) =>
      _RenderFindSurface(region);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFindSurface renderObject,
  ) {
    renderObject.region = region;
  }
}

class _RenderFindSurface extends RenderProxyBoxWithHitTestBehavior {
  _RenderFindSurface(this.region)
      : super(behavior: HitTestBehavior.translucent);

  _ContextualFindRegionState region;
}
