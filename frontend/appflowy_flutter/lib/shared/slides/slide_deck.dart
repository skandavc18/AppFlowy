import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/slides/slide_card.dart';
import 'package:appflowy/shared/slides/slide_geometry.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Drives a deck from outside it.
class SlideDeckController extends ChangeNotifier {
  _SlideDeckState? _deck;

  /// The slide being read.
  int get index => _deck?._settled ?? 0;

  void next() => _deck?.step(1);

  void previous() => _deck?.step(-1);

  void goTo(int index, {bool animate = true}) =>
      _deck?.goTo(index, animate: animate);

  @override
  void dispose() {
    _deck = null;
    super.dispose();
  }
}

/// A rack of rows that can be moved through one at a time.
///
/// This is not a page view. A page view lays every child out at the viewport's
/// size and cannot overlap, tilt or scale them, which is most of what makes a
/// deck worth looking at. Instead the position is a plain number, the
/// arrangement is worked out by [SlideDeckLayout], and only the slides near
/// the middle are built at all.
class SlideDeck extends StatefulWidget {
  const SlideDeck({
    super.key,
    required this.cards,
    required this.palette,
    this.controller,
    this.flow = SlideFlow.deck,
    this.wrap = false,
    this.index = 0,
    this.showPageContent = false,
    this.highlighted,
    this.onIndexChanged,
    this.onOpen,
    this.onEdit,
    this.onContextMenu,
    this.onBackgroundContextMenu,
  });

  final List<SlideCardData> cards;
  final SlidePalette palette;
  final SlideDeckController? controller;
  final SlideFlow flow;
  final bool wrap;

  /// The slide the host would like shown.
  final int index;

  /// Whether each slide reads the row's own page.
  final bool showPageContent;

  /// The rows a search matched. Everything else is drawn quietly.
  final Set<String>? highlighted;

  /// Reports the final index after a gesture/animation settles, not every
  /// midpoint crossed while the reader is still moving the deck.
  final ValueChanged<int>? onIndexChanged;
  final void Function(SlideCardData card)? onOpen;
  final void Function(SlideCardData card)? onEdit;
  final void Function(SlideCardData card, Offset globalPosition)? onContextMenu;
  final void Function(Offset globalPosition)? onBackgroundContextMenu;

  @override
  State<SlideDeck> createState() => _SlideDeckState();
}

class _SlideDeckState extends State<SlideDeck>
    with SingleTickerProviderStateMixin {
  /// Where the deck is, measured in slides. 2.5 is halfway between the third
  /// and the fourth.
  final ValueNotifier<double> _position = ValueNotifier(0);

  late final AnimationController _drive;

  final FocusNode _focus = FocusNode(debugLabel: 'SlideDeck');

  double _from = 0;
  double _to = 0;
  int _settled = 0;
  int _reportedIndex = 0;

  /// Set while a drag is moving the deck, so it is not snapped back mid gesture.
  bool _dragging = false;
  bool _trackpadDragging = false;
  double _panStartPosition = 0;
  Timer? _wheelSettle;

  Size _stage = Size.zero;

  /// Slides already built, so moving the deck costs a transform rather than a
  /// rebuild of every card on it.
  final Map<String, Widget> _built = {};

  @override
  void initState() {
    super.initState();
    _drive = AnimationController(
      vsync: this,
      duration: SlideMetrics.settle,
    )..addListener(_onDrive);
    widget.controller?._deck = this;
    _settled = _clampIndex(widget.index);
    _reportedIndex = _settled;
    _position.value = _settled.toDouble();
  }

  @override
  void didUpdateWidget(SlideDeck old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._deck = null;
      widget.controller?._deck = this;
    }
    if (!identical(old.cards, widget.cards) ||
        old.palette != widget.palette ||
        old.flow != widget.flow ||
        old.showPageContent != widget.showPageContent ||
        old.highlighted != widget.highlighted) {
      _built.clear();
    }
    if (old.cards.length != widget.cards.length) {
      final clamped = _clampIndex(_settled);
      if (clamped != _settled) {
        _settled = clamped;
        _position.value = clamped.toDouble();
      }
    }
    if (old.index != widget.index &&
        widget.index != _settled &&
        !_dragging &&
        _wheelSettle == null) {
      goTo(widget.index);
    }
  }

  @override
  void dispose() {
    widget.controller?._deck = null;
    _wheelSettle?.cancel();
    _drive.dispose();
    _focus.dispose();
    _position.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- movement

  SlideDeckLayout get _layout => SlideDeckLayout(
        viewport: _stage,
        flow: widget.flow,
        wrap: widget.wrap,
      );

  int get _count => widget.cards.length;

  int _clampIndex(int index) {
    if (_count == 0) {
      return 0;
    }
    if (!widget.wrap) {
      return index.clamp(0, _count - 1);
    }
    final wrapped = index % _count;
    return wrapped < 0 ? wrapped + _count : wrapped;
  }

  void _onDrive() {
    final eased = SlideMetrics.settleCurve.transform(_drive.value);
    _setPosition(lerpDouble(_from, _to, eased)!);
    if (_drive.isCompleted) _reportSettledIndex();
  }

  void _reportSettledIndex() {
    if (_dragging || _reportedIndex == _settled) return;
    _reportedIndex = _settled;
    // The nearest card is live during a drag, but the host must not persist
    // each crossed midpoint or echo it back as another navigation animation.
    widget.onIndexChanged?.call(_settled);
  }

  void _setPosition(double value) {
    _position.value = value;
    final settled = _layout.settledIndex(value, _count);
    if (settled != _settled) {
      _settled = settled;
      // Only the two slides whose liveness changed need rebuilding.
      _built.clear();
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _glideTo(double target, {Duration? duration}) {
    _drive.stop();
    _from = _position.value;
    _to = target;
    if ((_to - _from).abs() < 0.0005 ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _setPosition(_to);
      _reportSettledIndex();
      return;
    }
    _drive
      ..duration = duration ?? SlideMetrics.settle
      ..value = 0
      ..forward();
  }

  void step(int by) => goTo(_settled + by);

  void goTo(int index, {bool animate = true}) {
    if (_count == 0) {
      return;
    }
    _wheelSettle?.cancel();
    _wheelSettle = null;
    final target = _clampIndex(index);
    final position = slideTargetPosition(
      from: _position.value,
      target: target,
      count: _count,
      wrap: widget.wrap,
    );
    if (animate) {
      _glideTo(position);
    } else {
      _drive.stop();
      _setPosition(position);
      _reportSettledIndex();
    }
  }

  /// Settles on whichever slide the deck is nearest.
  void _snap({double velocity = 0}) {
    if (_count == 0) {
      return;
    }
    var target = _position.value.round();
    if (velocity.abs() > SlideMetrics.flingVelocity) {
      // Carry to the next integer in the flick's direction. Adding another
      // slide after crossing the midpoint used to skip two slides at once.
      target = velocity < 0 ? _position.value.ceil() : _position.value.floor();
    }
    if (!widget.wrap) {
      target = target.clamp(0, _count - 1);
    }
    _glideTo(target.toDouble());
  }

  void _nudge(double slides) {
    _drive.stop();
    final give = widget.wrap ? 0.0 : 0.25;
    _setPosition(
      _layout.clampPosition(_position.value + slides, _count, give: give),
    );
  }

  // ---------------------------------------------------------------- gestures

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _count == 0) {
      return;
    }
    // Descendant property scrollers and maps register first. A raw listener
    // used to move the deck even when one of them (or the page) also scrolled.
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      _onResolvedScroll,
    );
  }

  void _onResolvedScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _dragging || _count == 0) return;
    final delta = event.scrollDelta;
    // A deck reads sideways, so a plain wheel drives it too.
    final amount = delta.dx.abs() > delta.dy.abs() ? delta.dx : delta.dy;
    if (!amount.isFinite || amount == 0) {
      return;
    }
    _nudge(amount / 120 * SlideMetrics.wheelStep);
    _wheelSettle?.cancel();
    _wheelSettle = Timer(const Duration(milliseconds: 130), () {
      _wheelSettle = null;
      _snap();
    });
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _wheelSettle?.cancel();
    _wheelSettle = null;
    _drive.stop();
    _panStartPosition = _position.value;
    _dragging = true;
    _trackpadDragging = true;
  }

  void _onPanZoomUpdate(Offset pan) {
    if (!_trackpadDragging || _count == 0) {
      return;
    }
    final step = _layout.step;
    if (step <= 0) {
      return;
    }
    // Use the gesture's total once, including the samples used to classify
    // its axis. Neither a nested map nor a vertical scroll can move the deck.
    _setPosition(
      _layout.clampPosition(
        _panStartPosition - pan.dx / step,
        _count,
        give: widget.wrap ? 0 : 0.25,
      ),
    );
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    if (!_trackpadDragging) return;
    _trackpadDragging = false;
    _dragging = false;
    _snap();
  }

  void _onPanZoomCancel() {
    if (!_trackpadDragging) return;
    _trackpadDragging = false;
    _dragging = false;
    _glideTo(_panStartPosition.roundToDouble());
  }

  void _onDragStart(DragStartDetails details) {
    _wheelSettle?.cancel();
    _wheelSettle = null;
    _drive.stop();
    _dragging = true;
    _focus.requestFocus();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging || _count == 0) {
      return;
    }
    final step = _layout.step;
    if (step <= 0) {
      return;
    }
    _nudge(-details.delta.dx / step);
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    _snap(velocity: details.velocity.pixelsPerSecond.dx);
  }

  void _onDragCancel() {
    if (!_dragging || _trackpadDragging) return;
    _dragging = false;
    _snap();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.pageDown:
        step(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.pageUp:
        step(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        goTo(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        goTo(_count - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
        final card = _cardAt(_settled);
        if (card != null) {
          widget.onOpen?.call(card);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }
  }

  SlideCardData? _cardAt(int index) =>
      index >= 0 && index < _count ? widget.cards[index] : null;

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) => PremiumScrollExclusion(
        // Only the deck's viewport, not its host's header or page margins.
        // History checks this at gesture start; moving outside cannot transfer
        // an in-flight swipe to another owner.
        child: _buildDeck(context),
      );

  Widget _buildDeck(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stage = Size(constraints.maxWidth, constraints.maxHeight);
        if (stage != _stage) {
          _stage = stage;
          _built.clear();
        }
        if (stage.isEmpty) {
          return const SizedBox.expand();
        }

        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerSignal: _onScroll,
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                _SlideTrackpadGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        _SlideTrackpadGestureRecognizer>(
                  _SlideTrackpadGestureRecognizer.new,
                  (recognizer) => recognizer
                    ..onStart = _onPanZoomStart
                    ..onUpdate = _onPanZoomUpdate
                    ..onEnd = _onPanZoomEnd
                    ..onCancel = _onPanZoomCancel,
                ),
                // Trackpad input has its own axis/scale-aware arena member.
                // Handling it in both recognizers would move the deck twice.
                HorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        HorizontalDragGestureRecognizer>(
                  () => HorizontalDragGestureRecognizer(
                    supportedDevices: const {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.invertedStylus,
                    },
                  ),
                  (recognizer) => recognizer
                    ..onStart = _onDragStart
                    ..onUpdate = _onDragUpdate
                    ..onEnd = _onDragEnd
                    ..onCancel = _onDragCancel,
                ),
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (recognizer) => recognizer
                    ..onTapDown = ((_) => _focus.requestFocus())
                    ..onSecondaryTapUp = widget.onBackgroundContextMenu == null
                        ? null
                        : (details) => widget.onBackgroundContextMenu!(
                              details.globalPosition,
                            ),
                ),
              },
              child: ClipRect(
                child: SizedBox.expand(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _position,
                    builder: (context, position, _) =>
                        _buildStack(position, stage),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStack(double position, Size stage) {
    final layout = _layout;
    final card = layout.cardSize;
    final left = (stage.width - card.width) / 2;
    final top = (stage.height - card.height) / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final placement in layout.placements(position, _count))
          Positioned(
            left: left,
            top: top,
            width: card.width,
            height: card.height,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, SlideMetrics.perspective)
                ..translate(placement.dx)
                ..rotateY(placement.tilt)
                ..scale(placement.scale),
              child: Opacity(
                opacity: placement.opacity.clamp(0.0, 1.0),
                child: _slideAt(placement, card),
              ),
            ),
          ),
      ],
    );
  }

  /// The built slide for a placement.
  ///
  /// The same widget instance is handed back every frame while nothing about
  /// it has changed, so Flutter skips the whole subtree and a move costs only
  /// the transform above it.
  Widget _slideAt(SlidePlacement placement, Size size) {
    final card = _cardAt(placement.index);
    if (card == null) {
      return const SizedBox.shrink();
    }
    final live = placement.index == _settled;
    final key = '${placement.index}|$live';
    return _built.putIfAbsent(
      key,
      () => RepaintBoundary(
        child: _dim(
          card,
          SlideCard(
            key: ValueKey(card.rowId),
            card: card,
            palette: widget.palette,
            size: size,
            prominence: placement.prominence,
            live: live,
            showPageContent: widget.showPageContent,
            onOpen: widget.onOpen == null
                ? null
                : () => _openOrCentre(placement.index, card),
            onEdit: widget.onEdit == null ? null : () => widget.onEdit!(card),
            onContextMenu: widget.onContextMenu == null
                ? null
                : (position) => widget.onContextMenu!(card, position),
          ),
        ),
      ),
    );
  }

  /// A search that matched nothing here leaves the slide standing, but quiet.
  Widget _dim(SlideCardData card, Widget child) {
    final matches = widget.highlighted;
    if (matches == null || matches.contains(card.rowId)) {
      return child;
    }
    return Opacity(opacity: 0.35, child: child);
  }

  /// Clicking a neighbour brings it forward; clicking the slide in front
  /// opens its row. Anything else makes the deck feel like a list of buttons.
  void _openOrCentre(int index, SlideCardData card) {
    if (index == _settled) {
      widget.onOpen?.call(card);
      return;
    }
    goTo(index);
  }
}

/// A deck owns deliberate sideways trackpad movement, not a vertical property
/// scroll or a pinch on a map. Unlike a Listener, this only reports movement
/// after winning the arena whose hit test was captured at gesture start.
class _SlideTrackpadGestureRecognizer extends OneSequenceGestureRecognizer {
  _SlideTrackpadGestureRecognizer()
      : super(supportedDevices: const {PointerDeviceKind.trackpad});

  ValueChanged<PointerPanZoomStartEvent>? onStart;
  ValueChanged<Offset>? onUpdate;
  ValueChanged<PointerPanZoomEndEvent>? onEnd;
  VoidCallback? onCancel;

  PointerPanZoomStartEvent? _start;
  Offset _pan = Offset.zero;
  bool _won = false;
  bool _horizontal = false;
  bool _started = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) => false;

  @override
  void addAllowedPointer(PointerDownEvent event) {}

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) =>
      _start == null && super.isPointerPanZoomAllowed(event);

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _start = event;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _start?.pointer) return;
    if (event is PointerPanZoomUpdateEvent) {
      if (!event.localPanDelta.isFinite ||
          !event.scale.isFinite ||
          !event.rotation.isFinite ||
          (event.scale - 1).abs() > 0.01 ||
          event.rotation.abs() > 0.01) {
        _reject();
        return;
      }
      // Flutter 3.27 transforms localPan as a point, including the viewport's
      // translation. Deltas preserve just the displacement and local scale in
      // the coordinate space captured when this recognizer started tracking.
      _pan += event.localPanDelta;
      if (!_horizontal) {
        if (_pan.dx.abs() < 12 && _pan.dy.abs() < 12) return;
        if (_pan.dx.abs() < 2 * _pan.dy.abs()) {
          _reject();
          return;
        }
        _horizontal = true;
        if (!_won) {
          resolve(GestureDisposition.accepted);
          return;
        }
      }
      _report();
    } else if (event is PointerPanZoomEndEvent) {
      final started = _started;
      _clear();
      if (started) {
        onEnd?.call(event);
      } else {
        resolve(GestureDisposition.rejected);
      }
    } else if (event is PointerCancelEvent) {
      _reject();
    }
  }

  void _report() {
    if (!_won || !_horizontal) return;
    if (!_started) {
      _started = true;
      onStart?.call(_start!);
    }
    onUpdate?.call(_pan);
  }

  void _reject() {
    final started = _started;
    _clear();
    resolve(GestureDisposition.rejected);
    if (started) onCancel?.call();
  }

  void _clear() {
    final pointer = _start?.pointer;
    _start = null;
    _pan = Offset.zero;
    _won = false;
    _horizontal = false;
    _started = false;
    if (pointer != null) stopTrackingPointer(pointer);
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer != _start?.pointer) return;
    _won = true;
    _report();
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer != _start?.pointer) return;
    final started = _started;
    _clear();
    if (started) onCancel?.call();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    // Disposing an active deck must not start a return animation or look up
    // MediaQuery through a deactivated ancestor from an onCancel callback.
    _clear();
    super.dispose();
  }

  @override
  String get debugDescription => 'slide trackpad swipe';
}

/// The little rail under a deck that says where in the table you are.
class SlideRail extends StatelessWidget {
  const SlideRail({
    super.key,
    required this.count,
    required this.index,
    required this.palette,
    this.onSelected,
  });

  final int count;
  final int index;
  final SlidePalette palette;
  final ValueChanged<int>? onSelected;

  /// Past this many rows the rail becomes a window onto the deck rather than
  /// one mark per row, which would be unreadable and unclickable.
  static const int maximumMarks = 24;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) {
      return const SizedBox.shrink();
    }
    final marks = math.min(count, maximumMarks);
    final first = _windowStart(marks);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < marks; i++)
          _buildMark(first + i, first + i == index),
      ],
    );
  }

  int _windowStart(int marks) {
    if (count <= marks) {
      return 0;
    }
    return (index - marks ~/ 2).clamp(0, count - marks);
  }

  Widget _buildMark(int at, bool active) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onSelected == null ? null : () => onSelected!(at),
          child: AnimatedContainer(
            duration: SlideMetrics.hover,
            curve: SlideMetrics.enterCurve,
            width: active ? SlideMetrics.railWidth : SlideMetrics.railHeight,
            height: SlideMetrics.railHeight,
            decoration: BoxDecoration(
              color: active
                  ? palette.accent
                  : palette.textMuted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(SlideMetrics.railHeight),
            ),
          ),
        ),
      ),
    );
  }
}
