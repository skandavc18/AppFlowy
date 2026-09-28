import 'dart:math' as math;

import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'database_find_navigation.dart';
import 'database_find_session.dart';

/// Adds read-only Find to the actual database surface, without owning its
/// controller, changing its layout, or reparenting its title/cells on open.
class DatabaseFindHost extends StatefulWidget {
  const DatabaseFindHost({
    super.key,
    required this.view,
    required this.child,
    this.isActive,
    this.readProvider,
    this.limits = const DocumentFindLimits(maxDepth: 0, maxViews: 1),
    this.delegateToNativeChild = false,
  });

  final ViewPB view;
  final Widget child;
  final bool Function()? isActive;

  /// Only native reads are injectable; matching, decoding and UI remain real.
  final DocumentFindReadProvider? readProvider;
  final DocumentFindLimits limits;

  /// A decorated alternative renderer can switch to a native tab view. Keep
  /// ONE region around its title/body, but search that native selected tab.
  final bool delegateToNativeChild;

  @override
  State<DatabaseFindHost> createState() => _DatabaseFindHostState();
}

class _DatabaseFindHostState extends State<DatabaseFindHost> {
  final _surfaceKey = GlobalKey();
  final _panelKey = GlobalKey();
  final _portal = OverlayPortalController();
  final _query = TextEditingController();
  final _findFocus = FocusNode(debugLabel: 'Database find');
  final _findScope = FocusScopeNode(debugLabel: 'Database find controls');
  DatabaseFindSession? _session;
  late final DatabaseFindController _navigation;
  DatabaseFindController? _drivenNavigation;
  _DatabaseFindHostState? _parent;
  _DatabaseFindHostState? _delegate;
  FocusNode? _previousFocus;
  late String _boundViewId;
  Object? _metadata;
  Rect? _lastBounds;
  bool _elementActive = true;
  bool _refreshQueued = false;
  int _epoch = 0;

  _DatabaseFindHostState get _target => _delegate ?? this;
  bool get _locallyActive =>
      mounted && _elementActive && (widget.isActive?.call() ?? true);
  bool get _available =>
      _locallyActive && _target._locallyActive && _ownerBounds() != null;

  @override
  void initState() {
    super.initState();
    _boundViewId = widget.view.id;
    _metadata = _viewMetadata(widget.view);
    _navigation = DatabaseFindController(
      viewId: () => _boundViewId,
      isActive: () => _locallyActive && _visibleOwner(context),
      ownerBounds: _globalOwnerBounds,
    );
    _query.addListener(_queryChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var parent = widget.delegateToNativeChild
        ? null
        : context
            .dependOnInheritedWidgetOfExactType<_DatabaseFindDelegation>()
            ?.owner;
    if (parent != null &&
        ModalRoute.of(context) != ModalRoute.of(parent.context)) {
      parent = null;
    }
    if (!identical(parent, _parent)) {
      _parent?._detach(this);
      _dismiss();
      _parent = parent;
      _parent?._attach(this);
    }
    if (!_visibleOwner(context)) _dismiss();
  }

  @override
  void didUpdateWidget(covariant DatabaseFindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final metadata = _viewMetadata(widget.view);
    // ViewPB can be mutated in place; oldWidget.view is not an ID snapshot.
    final rebound = _boundViewId != widget.view.id ||
        oldWidget.readProvider != widget.readProvider ||
        oldWidget.limits != widget.limits;
    if (rebound) {
      _dismiss();
      _parent?._dismiss();
    } else if (_metadata != metadata) {
      _session?.invalidate();
      _parent?._session?.invalidate();
    }
    _boundViewId = widget.view.id;
    _metadata = metadata;
    if (!_locallyActive) {
      _dismiss();
      _parent?._dismiss();
    }
  }

  void _attach(_DatabaseFindHostState child) {
    if (identical(_delegate, child)) return;
    _delegate = child;
    _dismiss();
  }

  void _detach(_DatabaseFindHostState child) {
    if (!identical(_delegate, child)) return;
    _delegate = null;
    _dismiss();
  }

  void _queryChanged() {
    final session = _session;
    if (session != null) session.search(_query.text, session.options);
  }

  void _show() {
    if (!_available || Overlay.maybeOf(context, rootOverlay: true) == null) {
      return;
    }
    final previous = FocusManager.instance.primaryFocus;
    if (_session == null) {
      final target = _target;
      final id = target.widget.view.id;
      if (id.isEmpty) return;
      // Dismissal can run during deactivation/rebinding, while query widgets
      // still listen to this controller. Reset only on a fresh, explicit open,
      // before installing a session, so clearing cannot start another read.
      _query.clear();
      _previousFocus = previous;
      late final DatabaseFindSession session;
      session = DatabaseFindSession(
        viewId: id,
        provider: target.widget.readProvider ?? widget.readProvider,
        limits: target.widget.limits,
        viewSnapshot: target._navigation.snapshot,
        isOwnerActive: () =>
            identical(_session, session) &&
            identical(_target, target) &&
            target.widget.view.id == id &&
            _available,
      );
      _session = session;
      _drivenNavigation = target._navigation
        ..addListener(_refresh)
        ..bind(
          session,
          avoidBounds: _panelBounds,
          ownsFocus: () => _findScope.hasFocus,
        );
      final epoch = ++_epoch;
      _lastBounds = _ownerBounds();
      _portal.show();
      _refresh();
      WidgetsBinding.instance.addPostFrameCallback((_) => _watchOwner(epoch));
    }
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A request from an earlier callback in this frame may still be pending.
      // Resolve it before comparing primaryFocus; otherwise Find can overwrite
      // the newer request. This public API is safe in the post-frame phase.
      FocusManager.instance.applyFocusChangesIfNeeded();
      if (!mounted || epoch != _epoch || _session == null || !_available) {
        return;
      }
      // A later click/query owns its focus. Opening this overlay is not a
      // licence for a delayed request to take that focus back.
      if (FocusManager.instance.primaryFocus != previous &&
          !_findScope.hasFocus) {
        return;
      }
      _query.selection =
          TextSelection(baseOffset: 0, extentOffset: _query.text.length);
      _findFocus.requestFocus();
    });
  }

  void _watchOwner(int epoch) {
    if (!mounted || epoch != _epoch || _session == null) return;
    if (!_available) {
      _dismiss();
      return;
    }
    final bounds = _ownerBounds();
    if (bounds != _lastBounds) {
      _lastBounds = bounds;
      _refresh();
    }
    // Observe existing frames, not a polling timer or self-scheduling ticker.
    WidgetsBinding.instance.addPostFrameCallback((_) => _watchOwner(epoch));
  }

  void _dismiss({bool restoreFocus = false}) {
    final session = _session;
    if (session == null) return;
    final previous = _previousFocus;
    final restore = restoreFocus && _findScope.hasFocus && _available;
    ++_epoch;
    _session = null;
    _previousFocus = null;
    _drivenNavigation?.removeListener(_refresh);
    _drivenNavigation?.bind(null);
    _drivenNavigation = null;
    session.dispose();
    _refresh();
    if (restore &&
        previous?.context?.mounted == true &&
        previous!.canRequestFocus &&
        ModalRoute.of(previous.context!) == ModalRoute.of(context)) {
      previous.requestFocus();
    }
  }

  void _refresh() {
    void refresh() {
      _refreshQueued = false;
      if (!mounted || !_elementActive) return;
      if (_session == null && _portal.isShowing) _portal.hide();
      setState(() {});
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_refreshQueued) return;
      _refreshQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
    } else {
      refresh();
    }
  }

  @override
  void deactivate() {
    _elementActive = false;
    _parent?._detach(this);
    _dismiss();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _elementActive = true;
    _parent?._attach(this);
    _refresh();
  }

  @override
  void dispose() {
    _elementActive = false;
    ++_epoch;
    _parent?._detach(this);
    _drivenNavigation?.removeListener(_refresh);
    _drivenNavigation?.bind(null);
    _drivenNavigation = null;
    _session?.dispose();
    _session = null;
    _navigation.dispose();
    _query.dispose();
    _findFocus.dispose();
    _findScope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _DatabaseFindDelegation(
      owner: widget.delegateToNativeChild ? this : null,
      child: DatabaseFindScope(
        controller: _navigation,
        child: KeyedSubtree(key: _surfaceKey, child: widget.child),
      ),
    );
    // The outer decoration remains the owner even while its native child
    // changes tabs. Do not install a second region/overlay for that child.
    if (_parent != null) return child;
    return ContextualFindRegion(
      debugLabel: 'Database find',
      onFind: _show,
      onDismiss: _dismiss,
      findOpen: _session != null,
      findFocusNode: _findScope,
      isActive: () => _available,
      child: CallbackShortcuts(
        bindings: {
          if (_session != null) ...{
            const SingleActivator(LogicalKeyboardKey.f3): () =>
                _session?.navigate(),
            const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
                _session?.navigate(forward: false),
          },
        },
        child: OverlayPortal.targetsRootOverlay(
          controller: _portal,
          overlayChildBuilder: _buildOverlay,
          child: child,
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final session = _session;
    final bounds = _ownerBounds();
    if (session == null || !_available || bounds == null) {
      return const SizedBox.shrink();
    }
    final margin = math.min(8.0, bounds.shortestSide / 4);
    final horizontalMargin =
        math.min(margin, math.max(0.0, (bounds.width - 180) / 2));
    final width =
        math.min(FindBarMetrics.maxWidth, bounds.width - horizontalMargin * 2);
    final navigation = _drivenNavigation!;
    final globalMatch = navigation.currentBounds;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject();
    final match = globalMatch != null && overlay is RenderBox
        ? Rect.fromPoints(
            overlay.globalToLocal(globalMatch.topLeft),
            overlay.globalToLocal(globalMatch.bottomRight),
          )
        : null;
    // The overlay may move, but never the database/editor subtree. Limiting
    // the scrolling details panel leaves an unobscured corner for the match.
    final maxHeight = math.max(
      0.0,
      math.min(bounds.height - margin * 2, bounds.height * 0.45),
    );
    final panel = _panelKey.currentContext?.findRenderObject();
    final height = panel is RenderBox && panel.hasSize
        ? math.min(panel.size.height, maxHeight)
        : maxHeight;
    final candidates = [
      Offset(bounds.right - horizontalMargin - width, bounds.top + margin),
      Offset(
        bounds.right - horizontalMargin - width,
        bounds.bottom - margin - height,
      ),
      Offset(bounds.left + horizontalMargin, bounds.top + margin),
      Offset(bounds.left + horizontalMargin, bounds.bottom - margin - height),
    ];
    final position = match == null
        ? candidates.first
        : candidates.firstWhere(
            (offset) =>
                !(offset & Size(width, height)).overlaps(match.inflate(4)),
            orElse: () => candidates.first,
          );
    return Positioned(
      top: position.dy,
      left: position.dx,
      width: width,
      child: ConstrainedBox(
        key: _panelKey,
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          primary: false,
          child: SingleChildScrollView(
            primary: false,
            scrollDirection: Axis.horizontal,
            // Keep this hierarchy constant even when a pane crosses 180px.
            child: SizedBox(
              width: math.max(180.0, width),
              child: FocusScope(
                node: _findScope,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.f3): () =>
                        session.navigate(),
                    const SingleActivator(LogicalKeyboardKey.f3, shift: true):
                        () => session.navigate(forward: false),
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                    ): () => session.navigate(forward: false),
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: TextFieldTapRegion(
                      child: TapRegion(
                        groupId: _query,
                        child: ListenableBuilder(
                          listenable: session,
                          builder: (context, _) => _DatabaseFindPanel(
                            session: session,
                            navigation: navigation,
                            query: _query,
                            focus: _findFocus,
                            onClose: () => _dismiss(restoreFocus: true),
                            onOutside: _dismiss,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect? _panelBounds() {
    final box = _panelKey.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize
        ? MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          )
        : null;
  }

  Rect? _globalOwnerBounds() {
    final bounds = _ownerBounds();
    if (bounds == null) return null;
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true)?.context.findRenderObject();
    return overlay is RenderBox
        ? MatrixUtils.transformRect(overlay.getTransformTo(null), bounds)
        : null;
  }

  Rect? _ownerBounds() {
    if (!mounted || !_elementActive || !_visibleOwner(context)) return null;
    final box = _surfaceKey.currentContext?.findRenderObject();
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true)?.context.findRenderObject();
    if (box is! RenderBox ||
        overlay is! RenderBox ||
        !box.attached ||
        !overlay.attached ||
        !box.hasSize ||
        !overlay.hasSize ||
        box.size.isEmpty ||
        !box.size.isFinite) {
      return null;
    }
    var bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    RenderObject child = box;
    for (var parent = child.parent; parent != null; parent = child.parent) {
      if (!parent.attached || !parent.paintsChild(child)) return null;
      if (parent is RenderSliver && parent.geometry?.visible != true) {
        return null;
      }
      if (parent is RenderIndexedStack) {
        if (parent.index == null) return null;
        var displayed = parent.firstChild;
        for (var i = 0; i < parent.index! && displayed != null; i++) {
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
      child = parent;
    }
    final media = MediaQuery.maybeOf(context);
    final padding = media?.padding ?? EdgeInsets.zero;
    final safe = Rect.fromLTRB(
      padding.left,
      padding.top,
      overlay.size.width - padding.right,
      overlay.size.height - padding.bottom - (media?.viewInsets.bottom ?? 0),
    );
    bounds = Rect.fromPoints(
      overlay.globalToLocal(bounds.topLeft),
      overlay.globalToLocal(bounds.bottomRight),
    ).intersect(safe);
    return bounds.isFinite && !bounds.isEmpty ? bounds : null;
  }
}

Object _viewMetadata(ViewPB view) =>
    (view.id, view.name, view.layout, view.extra, view.lastEdited.toString());

bool _visibleOwner(BuildContext context) {
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
  var visible = true;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if ((widget is Offstage && widget.offstage) ||
        (widget is Visibility && !widget.visible) ||
        (widget is TickerMode && !widget.enabled)) {
      visible = false;
      return false;
    }
    return true;
  });
  return visible;
}

class _DatabaseFindDelegation extends InheritedWidget {
  const _DatabaseFindDelegation({required this.owner, required super.child});
  final _DatabaseFindHostState? owner;

  @override
  bool updateShouldNotify(_DatabaseFindDelegation oldWidget) =>
      owner != oldWidget.owner;
}

class _DatabaseFindPanel extends StatelessWidget {
  const _DatabaseFindPanel({
    required this.session,
    required this.navigation,
    required this.query,
    required this.focus,
    required this.onClose,
    required this.onOutside,
  });

  final DatabaseFindSession session;
  final DatabaseFindController navigation;
  final TextEditingController query;
  final FocusNode focus;
  final VoidCallback onClose;
  final VoidCallback onOutside;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final current = session.current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FindReplaceBar(
          findController: query,
          findFocusNode: focus,
          options: session.options,
          onOptionsChanged: (options) => session.search(query.text, options),
          matchCount: session.matches.length,
          currentMatch: session.currentMatch,
          onPrevious:
              current == null ? null : () => session.navigate(forward: false),
          onNext: current == null ? null : () => session.navigate(),
          onSubmitted: () => session.navigate(
            forward: !HardwareKeyboard.instance.isShiftPressed,
          ),
          onClose: onClose,
          onTapOutside: onOutside,
          queryInvalid: session.queryInvalid,
          busy: session.loading,
          autofocus: false,
        ),
        Container(
          key: const ValueKey('databaseFindDetails'),
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  _status,
                  key: const ValueKey('databaseFindStatus'),
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ),
              if (current != null) ...[
                if (navigation.message != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    navigation.message!,
                    key: const ValueKey('databaseFindNavigationStatus'),
                    style:
                        TextStyle(fontSize: 12, color: palette.textSecondary),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  current.part.location,
                  key: const ValueKey('databaseFindLocation'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                _snippet(current, palette),
              ],
              const SizedBox(height: 8),
              Text(
                'Current view only: title, columns and saved visible-row values. '
                'Related rows, encrypted values and image/file contents are not searched. '
                'Up to ${session.limits.maxEntries} entries/matches and '
                '${session.limits.maxBytes ~/ 1024} KiB of text; native responses may be larger.',
                style: TextStyle(fontSize: 11, color: palette.textSecondary),
              ),
              if (const {
                DatabaseFindStatus.denied,
                DatabaseFindStatus.failed,
                DatabaseFindStatus.timedOut,
                DatabaseFindStatus.changed,
              }.contains(session.status))
                TextButton(
                  key: const ValueKey('databaseFindRetry'),
                  onPressed: session.invalidate,
                  child: Text(
                    'Retry search',
                    style: TextStyle(color: palette.accent),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String get _status => switch (session.status) {
        DatabaseFindStatus.idle => 'Find in this database view · Read only',
        DatabaseFindStatus.loading => 'Searching current database view…',
        DatabaseFindStatus.denied =>
          'Database unavailable or access denied. No content was published.',
        DatabaseFindStatus.failed =>
          'Database search failed. Retry to read the current view again.',
        DatabaseFindStatus.timedOut =>
          'Search deadline reached. The unfinished read is still pending; no stale results are shown.',
        DatabaseFindStatus.changed =>
          'Database changed during search. Retry for current results.',
        DatabaseFindStatus.ready => [
            if (session.coverageUnknown)
              'native row/cell coverage could not be verified',
            if (session.unavailable)
              'some values are unavailable or unsupported',
            if (session.truncated) 'search limit reached',
          ].isEmpty
              ? 'Read-only results in the current database view'
              : 'Partial search: ${[
                  if (session.coverageUnknown)
                    'native row/cell coverage could not be verified',
                  if (session.unavailable)
                    'some values are unavailable or unsupported',
                  if (session.truncated) 'search limit reached',
                ].join('; ')}.',
      };

  Widget _snippet(DatabaseFindMatch result, FindBarPalette palette) {
    final text = result.part.text;
    final start = math.max(0, result.range.start - 64);
    final highlightedEnd = math.min(result.range.end, result.range.start + 160);
    final end = math.min(text.length, result.range.end + 64);
    return Text.rich(
      TextSpan(
        children: [
          if (start > 0) const TextSpan(text: '…'),
          TextSpan(text: text.substring(start, result.range.start)),
          TextSpan(
            text: text.substring(result.range.start, highlightedEnd),
            style: TextStyle(
              backgroundColor: palette.selected,
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (highlightedEnd < result.range.end) const TextSpan(text: '…'),
          TextSpan(text: text.substring(result.range.end, end)),
          if (end < text.length) const TextSpan(text: '…'),
        ],
      ),
      key: const ValueKey('databaseFindSnippet'),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: palette.textPrimary),
    );
  }
}
