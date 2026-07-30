import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_menu_entry.dart';
import 'app_menu_style.dart';
import 'app_menu_surface.dart';

/// Where a menu sits relative to the thing that opened it.
enum AppMenuPlacement {
  /// Top-left corner at the anchor point — a right-click menu.
  pointer,

  /// Under the anchor, left edges aligned — a dropdown.
  below,

  /// Under the anchor, right edges aligned — an overflow button near the
  /// right edge of a toolbar.
  belowEnd,

  /// Over the anchor, left edges aligned.
  above,

  /// Beside the anchor, tops aligned — a submenu.
  endTop,

  /// Mirror of [endTop], used when a submenu would run off the screen.
  startTop;

  bool get isSubmenu => this == endTop || this == startTop;
}

/// Lets an [AppMenuCustom] row close the menu it lives in.
class AppMenuScope extends InheritedWidget {
  const AppMenuScope({
    super.key,
    required this.close,
    required super.child,
  });

  /// Dismisses the whole menu, optionally returning a value.
  final void Function([Object? value]) close;

  static AppMenuScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppMenuScope>();

  @override
  bool updateShouldNotify(AppMenuScope oldWidget) => close != oldWidget.close;
}

/// Shows the one context menu the whole application uses.
///
/// Provide either [globalPosition] (a right click) or [anchor] (a button's
/// global rect). The menu positions itself to stay on screen, opens submenus
/// on hover, and supports full keyboard navigation.
Future<T?> showAppMenu<T>({
  required BuildContext context,
  required List<AppMenuEntry> entries,
  Offset? globalPosition,
  Rect? anchor,
  AppMenuPlacement placement = AppMenuPlacement.pointer,
  double? width,
  double maxHeight = AppMenuMetrics.defaultMaxHeight,
  bool useRootNavigator = true,
}) {
  assert(
    globalPosition != null || anchor != null,
    'showAppMenu needs a pointer position or an anchor rect',
  );

  final normalized = normalizeAppMenuEntries(entries);
  if (normalized.isEmpty) {
    return Future<T?>.value();
  }

  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final globalAnchor = anchor ?? (globalPosition! & Size.zero);
  final overlayBox =
      navigator.overlay?.context.findRenderObject() as RenderBox?;
  final localAnchor = overlayBox == null || !overlayBox.hasSize
      ? globalAnchor
      : Rect.fromPoints(
          overlayBox.globalToLocal(globalAnchor.topLeft),
          overlayBox.globalToLocal(globalAnchor.bottomRight),
        );

  return navigator.push<T>(
    _AppMenuRoute<T>(
      entries: normalized,
      anchor: localAnchor,
      placement: placement,
      width: width,
      maxHeight: maxHeight,
      capturedThemes:
          InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// Shows a menu anchored to the widget that owns [context] — the shape every
/// three-dot and overflow button uses.
Future<T?> showAppMenuForWidget<T>({
  required BuildContext context,
  required List<AppMenuEntry> entries,
  AppMenuPlacement placement = AppMenuPlacement.belowEnd,
  double? width,
  double maxHeight = AppMenuMetrics.defaultMaxHeight,
  Offset offset = Offset.zero,
}) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    return Future<T?>.value();
  }
  final topLeft = box.localToGlobal(Offset.zero) + offset;
  return showAppMenu<T>(
    context: context,
    entries: entries,
    anchor: topLeft & box.size,
    placement: placement,
    width: width,
    maxHeight: maxHeight,
  );
}

class _AppMenuRoute<T> extends PopupRoute<T> {
  _AppMenuRoute({
    required this.entries,
    required this.anchor,
    required this.placement,
    required this.width,
    required this.maxHeight,
    required this.capturedThemes,
    required this.barrierLabel,
  });

  final List<AppMenuEntry> entries;
  final Rect anchor;
  final AppMenuPlacement placement;
  final double? width;
  final double maxHeight;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => AppMenuMetrics.openDuration;

  @override
  Duration get reverseTransitionDuration => AppMenuMetrics.closeDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return capturedThemes.wrap(
      _AppMenuStack(
        entries: entries,
        anchor: anchor,
        placement: placement,
        width: width,
        maxHeight: maxHeight,
        animation: animation,
        onDismiss: (value) {
          if (!isActive) {
            return;
          }
          navigator?.pop(value is T ? value : null);
        },
      ),
    );
  }

  // The card animates itself so it grows from its own corner; scaling the
  // full-screen page would fly it in from the window corner instead.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

class _MenuLevel {
  _MenuLevel({
    required this.entries,
    required this.anchor,
    required this.placement,
    required this.parentIndex,
  });

  final List<AppMenuEntry> entries;

  /// The rect this level hangs off, in overlay coordinates: the trigger for
  /// the root level, the parent row for a submenu.
  final Rect anchor;

  final AppMenuPlacement placement;

  /// Index of the row in the parent level that opened this one, or -1.
  final int parentIndex;

  final GlobalKey cardKey = GlobalKey();
  final Map<int, GlobalKey> rowKeys = <int, GlobalKey>{};
  final ScrollController scrollController = ScrollController();

  int highlighted = -1;

  void dispose() => scrollController.dispose();
}

class _AppMenuStack extends StatefulWidget {
  const _AppMenuStack({
    required this.entries,
    required this.anchor,
    required this.placement,
    required this.width,
    required this.maxHeight,
    required this.animation,
    required this.onDismiss,
  });

  final List<AppMenuEntry> entries;
  final Rect anchor;
  final AppMenuPlacement placement;
  final double? width;
  final double maxHeight;
  final Animation<double> animation;
  final void Function(Object? value) onDismiss;

  @override
  State<_AppMenuStack> createState() => _AppMenuStackState();
}

class _AppMenuStackState extends State<_AppMenuStack> {
  final GlobalKey _rootKey = GlobalKey();
  final FocusNode _focusNode = FocusNode(debugLabel: 'app_context_menu');
  final List<_MenuLevel> _levels = <_MenuLevel>[];

  Timer? _openTimer;
  Timer? _closeTimer;
  Timer? _aimTimer;

  /// The pointer's last two positions in overlay coordinates, which is all the
  /// hover-intent test needs to know which way the pointer is travelling.
  Offset? _pointer;
  Offset? _previousPointer;
  DateTime? _aimingSince;

  /// Levels the pointer is currently inside, so a submenu only closes once the
  /// pointer has left both it and its parent.
  final Set<int> _hoveredLevels = <int>{};

  @override
  void initState() {
    super.initState();
    _levels.add(
      _MenuLevel(
        entries: widget.entries,
        anchor: widget.anchor,
        placement: widget.placement,
        parentIndex: -1,
      ),
    );
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _aimTimer?.cancel();
    for (final level in _levels) {
      level.dispose();
    }
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = AppMenuStyle.of(context);
    final safeArea = MediaQuery.paddingOf(context);

    return AppMenuScope(
      close: ([value]) => widget.onDismiss(value),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        // Nothing wraps the stack: a full-screen pointer region here would
        // report every hit as a miss and let the barrier dismiss the menu
        // from under its own rows.
        child: Stack(
          key: _rootKey,
          children: [
            for (var i = 0; i < _levels.length; i++)
              CustomSingleChildLayout(
                key: ValueKey<int>(i),
                delegate: _AppMenuLayout(
                  anchor: _levels[i].anchor,
                  placement: _levels[i].placement,
                  safeArea: safeArea,
                  maxHeight: widget.maxHeight,
                ),
                child: _buildLevel(context, style, i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevel(BuildContext context, AppMenuStyle style, int index) {
    final level = _levels[index];
    final rows = <Widget>[];

    for (var i = 0; i < level.entries.length; i++) {
      final entry = level.entries[i];
      switch (entry) {
        case AppMenuSeparator():
          rows.add(AppMenuSeparatorLine(style: style));
        case AppMenuHeader(:final label):
          rows.add(AppMenuSectionLabel(label: label, style: style));
        case AppMenuCustom(:final builder):
          rows.add(Builder(builder: builder));
        case AppMenuItem():
          final rowIndex = i;
          rows.add(
            KeyedSubtree(
              key: level.rowKeys.putIfAbsent(rowIndex, GlobalKey.new),
              child: AppMenuRow(
                label: entry.label,
                icon: entry.icon,
                iconWidget: entry.iconWidget,
                subtitle: entry.subtitle,
                shortcut: entry.shortcut,
                trailing: entry.trailing,
                hasSubmenu: entry.hasSubmenu,
                enabled: entry.enabled,
                selected: entry.selected,
                destructive: entry.destructive,
                highlighted: level.highlighted == rowIndex,
                style: style,
                onHover: (_) => _onRowHover(index, rowIndex),
                onTap: () => _activate(index, rowIndex),
              ),
            ),
          );
      }
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );

    Widget card = AppMenuSurface(
      key: level.cardKey,
      style: style,
      width: widget.width,
      constraints: BoxConstraints(
        minWidth: widget.width ?? AppMenuMetrics.minWidth,
        maxWidth: widget.width ?? AppMenuMetrics.maxWidth,
      ),
      child: SingleChildScrollView(
        controller: level.scrollController,
        child: widget.width == null
            // Menus hug their longest row instead of every menu in the
            // application being one arbitrary width.
            ? IntrinsicWidth(child: content)
            : content,
      ),
    );

    card = MouseRegion(
      onEnter: (_) => _onLevelEnter(index),
      onHover: _trackPointer,
      onExit: (_) => _onLevelExit(index),
      child: Listener(
        // Clicking the card's own padding, or a row that happens to be
        // disabled, must not fall through to the barrier.
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );

    return index == 0
        ? _RootEntrance(
            animation: widget.animation,
            placement: level.placement,
            child: card,
          )
        : _SubmenuEntrance(placement: level.placement, child: card);
  }

  // ---------------------------------------------------------------- pointer

  void _trackPointer(PointerHoverEvent event) {
    final root = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (root == null || !root.hasSize) {
      return;
    }
    _previousPointer = _pointer;
    _pointer = root.globalToLocal(event.position);
  }

  void _onLevelEnter(int index) {
    _closeTimer?.cancel();
    _hoveredLevels.add(index);
  }

  void _onLevelExit(int index) {
    _hoveredLevels.remove(index);
    _closeTimer?.cancel();
    _closeTimer = Timer(AppMenuMetrics.submenuCloseDelay, () {
      if (!mounted) {
        return;
      }
      // Nothing under the pointer any more: fall back to the root menu, the
      // way a native menu does when you wander off it.
      final deepest =
          _hoveredLevels.isEmpty ? 0 : _hoveredLevels.reduce(math.max);
      _truncate(deepest + 1);
    });
  }

  void _onRowHover(int levelIndex, int rowIndex) {
    if (levelIndex >= _levels.length) {
      return;
    }
    _closeTimer?.cancel();

    final level = _levels[levelIndex];
    final entry = level.entries[rowIndex];
    final isItem = entry is AppMenuItem && entry.enabled;

    if (level.highlighted != rowIndex) {
      setState(() {
        level.highlighted = isItem ? rowIndex : -1;
        for (var i = levelIndex + 1; i < _levels.length; i++) {
          _levels[i].highlighted = -1;
        }
      });
    }

    final hasOpenChild = _levels.length > levelIndex + 1;
    if (hasOpenChild && _levels[levelIndex + 1].parentIndex == rowIndex) {
      // Already showing this row's submenu.
      _openTimer?.cancel();
      _aimTimer?.cancel();
      _aimingSince = null;
      return;
    }

    if (hasOpenChild && _isAimingAtSubmenu(levelIndex + 1)) {
      _scheduleAimRecheck(levelIndex, rowIndex);
      return;
    }

    _openTimer?.cancel();
    _aimTimer?.cancel();
    _aimingSince = null;

    if (hasOpenChild) {
      _truncate(levelIndex + 1);
    }

    if (entry is AppMenuItem && entry.enabled && entry.hasSubmenu) {
      _openTimer = Timer(
        AppMenuMetrics.submenuOpenDelay,
        () => _openSubmenu(levelIndex, rowIndex),
      );
    }
  }

  void _scheduleAimRecheck(int levelIndex, int rowIndex) {
    _aimingSince ??= DateTime.now();
    _aimTimer?.cancel();
    _aimTimer = Timer(AppMenuMetrics.aimRetryInterval, () {
      if (!mounted || levelIndex >= _levels.length) {
        return;
      }
      final level = _levels[levelIndex];
      if (level.highlighted != rowIndex) {
        return;
      }
      final started = _aimingSince;
      final expired = started != null &&
          DateTime.now().difference(started) > AppMenuMetrics.aimGracePeriod;
      if (!expired &&
          _levels.length > levelIndex + 1 &&
          _isAimingAtSubmenu(levelIndex + 1)) {
        _scheduleAimRecheck(levelIndex, rowIndex);
        return;
      }
      _aimingSince = null;
      _onRowHoverAfterAim(levelIndex, rowIndex);
    });
  }

  void _onRowHoverAfterAim(int levelIndex, int rowIndex) {
    if (_levels.length > levelIndex + 1) {
      _truncate(levelIndex + 1);
    }
    final entry = _levels[levelIndex].entries[rowIndex];
    if (entry is AppMenuItem && entry.enabled && entry.hasSubmenu) {
      _openSubmenu(levelIndex, rowIndex);
    }
  }

  /// Whether the pointer is travelling towards the open submenu rather than
  /// simply passing over a sibling row on its way there.
  ///
  /// The test is the classic one: take the triangle whose apex is where the
  /// pointer just was and whose base is the submenu's near edge. While the
  /// pointer stays inside it, the sibling under the cursor does not win.
  bool _isAimingAtSubmenu(int levelIndex) {
    final current = _pointer;
    final previous = _previousPointer;
    if (current == null || previous == null) {
      return false;
    }
    final rect = _rectOf(_levels[levelIndex].cardKey);
    if (rect == null) {
      return false;
    }

    final opensRight = rect.left >= current.dx;
    final edgeX = opensRight ? rect.left : rect.right;
    final travel = current.dx - previous.dx;
    if (opensRight ? travel <= 0 : travel >= 0) {
      return false;
    }
    if (opensRight ? current.dx > edgeX : current.dx < edgeX) {
      return false;
    }

    const slack = 12.0;
    return _insideTriangle(
      current,
      previous,
      Offset(edgeX, rect.top - slack),
      Offset(edgeX, rect.bottom + slack),
    );
  }

  static bool _insideTriangle(Offset p, Offset a, Offset b, Offset c) {
    double sign(Offset p1, Offset p2, Offset p3) =>
        (p1.dx - p3.dx) * (p2.dy - p3.dy) - (p2.dx - p3.dx) * (p1.dy - p3.dy);

    final d1 = sign(p, a, b);
    final d2 = sign(p, b, c);
    final d3 = sign(p, c, a);
    final hasNegative = d1 < 0 || d2 < 0 || d3 < 0;
    final hasPositive = d1 > 0 || d2 > 0 || d3 > 0;
    return !(hasNegative && hasPositive);
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final root = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || root == null || !box.hasSize || !root.hasSize) {
      return null;
    }
    return root.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
  }

  // ----------------------------------------------------------------- levels

  void _openSubmenu(int levelIndex, int rowIndex, {bool focusFirst = false}) {
    if (!mounted || levelIndex >= _levels.length) {
      return;
    }
    final level = _levels[levelIndex];
    final entry = level.entries[rowIndex];
    if (entry is! AppMenuItem || !entry.enabled || !entry.hasSubmenu) {
      return;
    }
    if (_levels.length > levelIndex + 1 &&
        _levels[levelIndex + 1].parentIndex == rowIndex) {
      if (focusFirst) {
        _highlightFirst(levelIndex + 1);
      }
      return;
    }

    final rowKey = level.rowKeys[rowIndex];
    final anchor = rowKey == null ? null : _rectOf(rowKey);
    if (anchor == null) {
      return;
    }

    // Only a hint for the slide direction — the layout delegate makes the
    // final call once it knows the submenu's real width.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final opensLeft = anchor.right + 240 > screenWidth;

    final child = _MenuLevel(
      entries: normalizeAppMenuEntries(entry.submenu),
      anchor: anchor,
      placement:
          opensLeft ? AppMenuPlacement.startTop : AppMenuPlacement.endTop,
      parentIndex: rowIndex,
    );

    setState(() {
      _disposeLevelsFrom(levelIndex + 1);
      _levels.add(child);
      if (focusFirst) {
        child.highlighted = _firstInteractive(child.entries);
      }
    });
  }

  void _truncate(int length) {
    if (length >= _levels.length || length < 1) {
      return;
    }
    setState(() => _disposeLevelsFrom(length));
  }

  void _disposeLevelsFrom(int index) {
    if (index >= _levels.length) {
      return;
    }
    final removed = _levels.sublist(index);
    _levels.removeRange(index, _levels.length);
    // The scroll views are still attached until this frame is over, so their
    // controllers cannot be disposed yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final level in removed) {
        level.dispose();
      }
    });
  }

  void _activate(int levelIndex, int rowIndex) {
    if (levelIndex >= _levels.length) {
      return;
    }
    final entry = _levels[levelIndex].entries[rowIndex];
    if (entry is! AppMenuItem || !entry.enabled) {
      return;
    }
    if (entry.hasSubmenu) {
      _openTimer?.cancel();
      _openSubmenu(levelIndex, rowIndex, focusFirst: true);
      return;
    }
    if (!entry.closeOnSelect) {
      entry.onSelected?.call();
      return;
    }

    widget.onDismiss(entry.value);

    final callback = entry.onSelected;
    if (callback != null) {
      // Run after this frame so a handler that opens a dialog or another menu
      // is not competing with the route that is on its way out.
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    }
  }

  // --------------------------------------------------------------- keyboard

  int _firstInteractive(List<AppMenuEntry> entries) {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is AppMenuItem && entry.isInteractive) {
        return i;
      }
    }
    return -1;
  }

  int _lastInteractive(List<AppMenuEntry> entries) {
    for (var i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (entry is AppMenuItem && entry.isInteractive) {
        return i;
      }
    }
    return -1;
  }

  void _highlightFirst(int levelIndex) {
    final level = _levels[levelIndex];
    setState(() => level.highlighted = _firstInteractive(level.entries));
    _revealHighlighted(levelIndex);
  }

  void _moveHighlight(int delta) {
    final levelIndex = _levels.length - 1;
    final level = _levels[levelIndex];
    final entries = level.entries;
    if (entries.isEmpty) {
      return;
    }

    var index = level.highlighted;
    for (var step = 0; step < entries.length; step++) {
      index = index < 0
          ? (delta > 0 ? 0 : entries.length - 1)
          : (index + delta) % entries.length;
      if (index < 0) {
        index += entries.length;
      }
      final entry = entries[index];
      if (entry is AppMenuItem && entry.isInteractive) {
        setState(() => level.highlighted = index);
        _revealHighlighted(levelIndex);
        // Keyboard travel must not drag submenus along with it.
        _truncate(levelIndex + 1);
        return;
      }
    }
  }

  void _revealHighlighted(int levelIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || levelIndex >= _levels.length) {
        return;
      }
      final level = _levels[levelIndex];
      final rowContext = level.rowKeys[level.highlighted]?.currentContext;
      if (rowContext == null) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          duration: AppMenuMetrics.submenuDuration,
          curve: AppMenuMetrics.enterCurve,
        ),
      );
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    final levelIndex = _levels.length - 1;
    final level = _levels[levelIndex];

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveHighlight(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveHighlight(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        setState(() => level.highlighted = _firstInteractive(level.entries));
        _revealHighlighted(levelIndex);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        setState(() => level.highlighted = _lastInteractive(level.entries));
        _revealHighlighted(levelIndex);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (level.highlighted >= 0) {
          _openSubmenu(levelIndex, level.highlighted, focusFirst: true);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (levelIndex > 0) {
          _truncate(levelIndex);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
        if (level.highlighted >= 0) {
          _activate(levelIndex, level.highlighted);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (levelIndex > 0) {
          _truncate(levelIndex);
        } else {
          widget.onDismiss(null);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        _moveHighlight(
          HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
        );
        return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}

/// Fade plus a slight grow, anchored on the corner nearest the trigger.
class _RootEntrance extends StatefulWidget {
  const _RootEntrance({
    required this.animation,
    required this.placement,
    required this.child,
  });

  final Animation<double> animation;
  final AppMenuPlacement placement;
  final Widget child;

  @override
  State<_RootEntrance> createState() => _RootEntranceState();
}

class _RootEntranceState extends State<_RootEntrance> {
  late CurvedAnimation _curved = _curve();

  CurvedAnimation _curve() => CurvedAnimation(
        parent: widget.animation,
        curve: AppMenuMetrics.enterCurve,
        reverseCurve: AppMenuMetrics.exitCurve,
      );

  @override
  void didUpdateWidget(_RootEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _curved.dispose();
      _curved = _curve();
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: AppMenuMetrics.openScale,
          end: 1,
        ).animate(_curved),
        alignment: switch (widget.placement) {
          AppMenuPlacement.belowEnd => Alignment.topRight,
          AppMenuPlacement.above => Alignment.bottomLeft,
          AppMenuPlacement.startTop => Alignment.topRight,
          _ => Alignment.topLeft,
        },
        child: widget.child,
      ),
    );
  }
}

/// Submenus fade and slide a few pixels out of their parent — never scale,
/// which would read as a second, unrelated popup.
class _SubmenuEntrance extends StatelessWidget {
  const _SubmenuEntrance({required this.placement, required this.child});

  final AppMenuPlacement placement;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final from = placement == AppMenuPlacement.startTop
        ? AppMenuMetrics.submenuSlide
        : -AppMenuMetrics.submenuSlide;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMenuMetrics.submenuDuration,
      curve: AppMenuMetrics.enterCurve,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(from * (1 - value), 0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _AppMenuLayout extends SingleChildLayoutDelegate {
  const _AppMenuLayout({
    required this.anchor,
    required this.placement,
    required this.safeArea,
    required this.maxHeight,
  });

  final Rect anchor;
  final AppMenuPlacement placement;
  final EdgeInsets safeArea;
  final double maxHeight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = BoxConstraints.loose(constraints.biggest).deflate(
      safeArea + const EdgeInsets.all(AppMenuMetrics.screenInset),
    );
    return available.copyWith(
      maxHeight: math.min(available.maxHeight, maxHeight),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minX = safeArea.left + AppMenuMetrics.screenInset;
    final minY = safeArea.top + AppMenuMetrics.screenInset;
    final maxX = size.width -
        safeArea.right -
        AppMenuMetrics.screenInset -
        childSize.width;
    final maxY = size.height -
        safeArea.bottom -
        AppMenuMetrics.screenInset -
        childSize.height;

    const gap = AppMenuMetrics.anchorGap;
    const submenuGap = AppMenuMetrics.submenuGap;
    final padTop = AppMenuMetrics.cardPadding.top;

    late final double preferredX;
    late final double? flippedX;
    late final double preferredY;
    late final double? flippedY;

    switch (placement) {
      case AppMenuPlacement.pointer:
        preferredX = anchor.left;
        flippedX = anchor.left - childSize.width;
        preferredY = anchor.top;
        flippedY = anchor.top - childSize.height;
      case AppMenuPlacement.below:
        preferredX = anchor.left;
        flippedX = anchor.right - childSize.width;
        preferredY = anchor.bottom + gap;
        flippedY = anchor.top - gap - childSize.height;
      case AppMenuPlacement.belowEnd:
        preferredX = anchor.right - childSize.width;
        flippedX = anchor.left;
        preferredY = anchor.bottom + gap;
        flippedY = anchor.top - gap - childSize.height;
      case AppMenuPlacement.above:
        preferredX = anchor.left;
        flippedX = anchor.right - childSize.width;
        preferredY = anchor.top - gap - childSize.height;
        flippedY = anchor.bottom + gap;
      case AppMenuPlacement.endTop:
        preferredX = anchor.right + submenuGap;
        flippedX = anchor.left - submenuGap - childSize.width;
        preferredY = anchor.top - padTop;
        flippedY = anchor.bottom + padTop - childSize.height;
      case AppMenuPlacement.startTop:
        preferredX = anchor.left - submenuGap - childSize.width;
        flippedX = anchor.right + submenuGap;
        preferredY = anchor.top - padTop;
        flippedY = anchor.bottom + padTop - childSize.height;
    }

    return Offset(
      _resolve(preferredX, flippedX, minX, maxX),
      _resolve(preferredY, flippedY, minY, maxY),
    );
  }

  static double _resolve(
    double preferred,
    double? flipped,
    double lo,
    double hi,
  ) {
    if (hi < lo) {
      return lo;
    }
    if (preferred >= lo && preferred <= hi) {
      return preferred;
    }
    if (flipped != null && flipped >= lo && flipped <= hi) {
      return flipped;
    }
    return preferred.clamp(lo, hi);
  }

  @override
  bool shouldRelayout(_AppMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      placement != oldDelegate.placement ||
      safeArea != oldDelegate.safeArea ||
      maxHeight != oldDelegate.maxHeight;
}
