import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/shared/context_menu/app_menu_style.dart';
import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import 'astrology_model.dart';
import 'astrology_style.dart';

/// A controlled suggestion surface anchored to [child], not its field label.
///
/// The caller owns search, focus, keyboard navigation and the selected place.
/// Use the same [groupId] on the editable TextField so a completed suggestion
/// tap reaches its button without first dismissing the field on pointer down.
class AstrologyPlaceDropdown extends StatefulWidget {
  const AstrologyPlaceDropdown({
    super.key,
    required this.child,
    required this.isOpen,
    required this.results,
    required this.busy,
    required this.highlightedIndex,
    required this.onSelected,
    this.message,
    this.onManualEntry,
    this.groupId = EditableText,
  });

  final Widget child;
  final bool isOpen;
  final List<AstrologyPlace> results;
  final bool busy;
  final int highlightedIndex;
  final ValueChanged<int> onSelected;
  final String? message;
  final VoidCallback? onManualEntry;
  final Object groupId;

  @override
  State<AstrologyPlaceDropdown> createState() => _AstrologyPlaceDropdownState();
}

class _AstrologyPlaceDropdownState extends State<AstrologyPlaceDropdown>
    with WidgetsBindingObserver {
  static const _maximumHeight = 320.0;
  static const _copyright = 'https://www.openstreetmap.org/copyright';

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _anchor = GlobalKey();
  final _scroll = ScrollController(keepScrollOffset: false);
  final _ancestorPositions = <ScrollPosition>{};
  late List<GlobalKey> _rowKeys;
  _DropdownPlacement? _placement;
  bool _attached = true;
  bool _syncScheduled = false;
  bool _revealScheduled = false;
  bool _needsReveal = true;
  bool _resetScroll = true;
  int _interactionEpoch = 0;

  @override
  void initState() {
    super.initState();
    _rowKeys = List.generate(widget.results.length, (_) => GlobalKey());
    WidgetsBinding.instance.addObserver(this);
    _scheduleSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recheck layout for inherited text scaling, safe areas and route changes.
    MediaQuery.of(context);
    ModalRoute.isCurrentOf(context);
    _needsReveal = true;
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant AstrologyPlaceDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _interactionEpoch++;
    if (!identical(oldWidget.results, widget.results) ||
        _rowKeys.length != widget.results.length) {
      _rowKeys = List.generate(widget.results.length, (_) => GlobalKey());
      _resetScroll = true;
      _needsReveal = true;
    }
    if (!oldWidget.isOpen && widget.isOpen) {
      _resetScroll = true;
      _needsReveal = true;
    }
    if (oldWidget.highlightedIndex != widget.highlightedIndex ||
        oldWidget.busy != widget.busy ||
        oldWidget.message != widget.message) {
      _needsReveal = true;
    }
    _scheduleSync();
  }

  @override
  void didChangeMetrics() => _scheduleSync();

  @override
  void deactivate() {
    _attached = false;
    _interactionEpoch++;
    _removeAncestorListeners();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _scheduleSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeAncestorListeners();
    _scroll.dispose();
    // OverlayPortal removes its own overlay child, including during an
    // ancestor's build. Calling hide here would mutate that retiring subtree.
    super.dispose();
  }

  void _removeAncestorListeners() {
    for (final position in _ancestorPositions) {
      position.removeListener(_scheduleSync);
    }
    _ancestorPositions.clear();
  }

  void _listenToAncestors() {
    final positions = <ScrollPosition>{};
    if (widget.isOpen) {
      context.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          positions.add((element.state as ScrollableState).position);
        }
        return true;
      });
    }
    for (final position in _ancestorPositions.difference(positions)) {
      position.removeListener(_scheduleSync);
    }
    for (final position in positions.difference(_ancestorPositions)) {
      position.addListener(_scheduleSync);
    }
    _ancestorPositions
      ..clear()
      ..addAll(positions);
  }

  void _scheduleSync() {
    if (!mounted ||
        !_attached ||
        _syncScheduled ||
        (!widget.isOpen && !_portal.isShowing && _ancestorPositions.isEmpty)) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted || !_attached) return;
      _listenToAncestors();
      final next = widget.isOpen ? _measurePlacement() : null;
      if (_placement != next) {
        setState(() => _placement = next);
        _needsReveal = true;
      }
      if (next == null) {
        if (_portal.isShowing) {
          _interactionEpoch++;
          _portal.hide();
        }
        return;
      }
      if (!_portal.isShowing) {
        _portal.show();
        _needsReveal = true;
      }
      if (_needsReveal) _scheduleReveal();
    });
    // A scroll/metrics notification can arrive between frames. No polling,
    // timers or persistent frame callbacks are needed while the field is idle.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  _DropdownPlacement? _measurePlacement() {
    if (!(ModalRoute.isCurrentOf(context) ?? true)) return null;
    final anchor = _anchor.currentContext?.findRenderObject();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final root = overlay?.context.findRenderObject();
    if (anchor is! RenderBox ||
        root is! RenderBox ||
        !anchor.attached ||
        !root.attached ||
        !anchor.hasSize ||
        !root.hasSize) {
      return null;
    }

    final media = MediaQuery.of(overlay!.context);
    final insets = media.padding + media.viewInsets;
    final window = Rect.fromLTRB(
      insets.left,
      insets.top,
      media.size.width - insets.right,
      media.size.height - insets.bottom,
    );
    if (!window.isFinite || window.isEmpty) return null;
    final available = Rect.fromPoints(
      root.globalToLocal(window.topLeft),
      root.globalToLocal(window.bottomRight),
    ).intersect(Offset.zero & root.size).deflate(AppMenuMetrics.screenInset);
    final field = MatrixUtils.transformRect(
      anchor.getTransformTo(root),
      Offset.zero & anchor.size,
    );
    if (!available.isFinite ||
        available.isEmpty ||
        !field.isFinite ||
        field.isEmpty) {
      return null;
    }

    // Ancestor clips govern whether the FIELD is visible, not how large its
    // popup may be. This includes both axes of nested scroll viewports and
    // clipped dashboard cards, without clipping the root-overlay surface.
    var visible = available;
    RenderObject child = anchor;
    while (child != root) {
      final parent = child.parent;
      if (parent == null) return null;
      if (parent is RenderOffstage && parent.offstage) return null;
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        visible = visible.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(root), clip),
        );
      }
      child = parent;
    }
    if (!visible.isFinite || visible.isEmpty || !visible.overlaps(field)) {
      return null;
    }

    const gap = AppMenuMetrics.anchorGap;
    final belowTop = math.max(available.top, field.bottom + gap);
    final aboveBottom = math.min(available.bottom, field.top - gap);
    final below = math.max(0.0, available.bottom - belowTop);
    final above = math.max(0.0, aboveBottom - available.top);
    final opensUp = below < 160 && above > below;
    final height = math.min(_maximumHeight, opensUp ? above : below);
    if (height <= 0) return null;
    final width = math.min(field.width, available.width);
    final left = field.left.clamp(available.left, available.right - width);
    return (
      opensUp: opensUp,
      width: width,
      maxHeight: height,
      offset: Offset(
        left - field.left,
        opensUp ? aboveBottom - field.top : belowTop - field.bottom,
      ),
    );
  }

  void _scheduleReveal() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted ||
          !_attached ||
          !widget.isOpen ||
          !_portal.isShowing ||
          _placement == null ||
          !_scroll.hasClients ||
          !_scroll.position.hasContentDimensions) {
        return;
      }
      _needsReveal = false;
      if (_resetScroll) {
        _resetScroll = false;
        _scroll.jumpTo(0);
      }
      final index = widget.highlightedIndex;
      if (index < 0 || index >= _rowKeys.length) return;
      final row = _rowKeys[index].currentContext?.findRenderObject();
      if (row == null || !row.attached) return;
      // Only this position may move. Scrollable.ensureVisible would also
      // walk the form/page ancestors retained by OverlayPortal.
      unawaited(_scroll.position.ensureVisible(row, alignment: 0.5));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openAttribution() async {
    if (!mounted || !widget.isOpen || !_portal.isShowing) return;
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(_copyright),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Missing platform support and browser failures are not search errors.
    }
    if (!opened &&
        mounted &&
        _attached &&
        widget.isOpen &&
        _portal.isShowing &&
        Scaffold.maybeOf(context) != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not open the browser. OpenStreetMap data is '
              'licensed under ODbL: $_copyright'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Capture at the field: inherited light/dark/paper tokens must not be
    // replaced by the root overlay's theme.
    final palette = AstrologyPalette.of(context);
    final menu = AppMenuStyle.of(context);
    return OverlayPortal.targetsRootOverlay(
      controller: _portal,
      overlayChildBuilder: (context) => _buildOverlay(context, palette, menu),
      child: CompositedTransformTarget(
        key: _anchor,
        link: _link,
        child: _AnchorLayoutObserver(
          onChanged: _scheduleSync,
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildOverlay(
    BuildContext context,
    AstrologyPalette palette,
    AppMenuStyle menu,
  ) {
    final placement = _placement;
    if (!widget.isOpen || placement == null) return const SizedBox.shrink();
    final onSelected = widget.onSelected;
    final onManualEntry = widget.onManualEntry;
    final epoch = _interactionEpoch;
    final results = widget.results;
    final busy = widget.busy;
    final message = widget.message ??
        (busy
            ? 'Searching places…'
            : results.isEmpty
                ? 'No places found.'
                : null);

    // Align loosens the overlay's tight, full-window constraints. Width alone
    // on a Container/SizedBox would still produce a window-sized popup.
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor:
            placement.opensUp ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor:
            placement.opensUp ? Alignment.bottomLeft : Alignment.topLeft,
        offset: placement.offset,
        child: TextFieldTapRegion(
          groupId: widget.groupId,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            descendantsAreFocusable: false,
            includeSemantics: false,
            child: SizedBox(
              width: placement.width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: placement.maxHeight),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: menu.borderRadius,
                    boxShadow: menu.shadows,
                  ),
                  child: Material(
                    key: const ValueKey('astrology-place-dropdown'),
                    color: palette.raised,
                    surfaceTintColor: palette.raised,
                    shape: RoundedRectangleBorder(
                      borderRadius: menu.borderRadius,
                      side: BorderSide(color: palette.line, width: 0.8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: ScrollConfiguration(
                            behavior: NoScrollbarBehavior(
                              ScrollConfiguration.of(context),
                            ),
                            child: SingleChildScrollView(
                              key: const ValueKey(
                                'astrology-place-suggestions-scroll',
                              ),
                              controller: _scroll,
                              primary: false,
                              // The inherited activation gate can be inactive
                              // on this same route. Keep its premium wheel
                              // decoration, but explicitly accept popup input.
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: AppMenuMetrics.cardPadding,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (message != null)
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: busy
                                                ? CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: palette.accent,
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              message,
                                              key: const ValueKey(
                                                'astrology-search-message',
                                              ),
                                              style:
                                                  menu.subtitleStyle.copyWith(
                                                color: palette.muted,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  for (var index = 0;
                                      index < results.length;
                                      index++)
                                    MergeSemantics(
                                      key: _rowKeys[index],
                                      child: Semantics(
                                        selected:
                                            widget.highlightedIndex == index,
                                        child: TextButton(
                                          key: ValueKey(
                                            'astrology-result-$index',
                                          ),
                                          onPressed: busy
                                              ? null
                                              : () {
                                                  if (!mounted ||
                                                      !_attached ||
                                                      !widget.isOpen ||
                                                      widget.busy ||
                                                      !_portal.isShowing ||
                                                      _placement == null ||
                                                      epoch !=
                                                          _interactionEpoch) {
                                                    return;
                                                  }
                                                  // Never late-read the new
                                                  // widget's generation-bound
                                                  // selection handler.
                                                  onSelected(index);
                                                },
                                          style: TextButton.styleFrom(
                                            alignment: Alignment.centerLeft,
                                            minimumSize: const Size(0, 48),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            foregroundColor: palette.ink,
                                            disabledForegroundColor:
                                                palette.muted,
                                            backgroundColor:
                                                widget.highlightedIndex == index
                                                    ? palette.selection
                                                    : palette.hover
                                                        .withValues(alpha: 0),
                                            overlayColor: palette.hover,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  menu.rowBorderRadius,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                results[index].name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: menu.labelStyle.copyWith(
                                                  color: busy
                                                      ? palette.muted
                                                      : palette.ink,
                                                  height: 1.25,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '${results[index].latitude.toStringAsFixed(4)}°, '
                                                '${results[index].longitude.toStringAsFixed(4)}° · '
                                                '${results[index].timeZone}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    menu.subtitleStyle.copyWith(
                                                  color: palette.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (onManualEntry != null)
                                    TextButton.icon(
                                      key: const ValueKey(
                                          'astrology-place-manual'),
                                      onPressed: () {
                                        if (mounted &&
                                            _attached &&
                                            widget.isOpen &&
                                            _portal.isShowing &&
                                            epoch == _interactionEpoch) {
                                          onManualEntry();
                                        }
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: palette.accent,
                                        overlayColor: palette.hover,
                                        alignment: Alignment.centerLeft,
                                        textStyle: menu.subtitleStyle,
                                      ),
                                      icon: const Icon(
                                        Icons.edit_location_alt_rounded,
                                        size: 16,
                                      ),
                                      label: const Text(
                                          'Enter coordinates manually'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Keep attribution visible instead of burying it after
                        // the results. Bound it too for very short windows/IME.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: placement.maxHeight / 2,
                          ),
                          child: ClipRect(
                            child: Semantics(
                              link: true,
                              child: TextButton(
                                onPressed: () => unawaited(_openAttribution()),
                                style: TextButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  foregroundColor: palette.muted,
                                  overlayColor: palette.hover,
                                  textStyle: menu.subtitleStyle,
                                ),
                                child: const Text(
                                  'Photon · © OpenStreetMap contributors',
                                  key: ValueKey('astrology-place-attribution'),
                                ),
                              ),
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
      ),
    );
  }
}

typedef _DropdownPlacement = ({
  bool opensUp,
  double width,
  double maxHeight,
  Offset offset,
});

/// Observe only actual layout/paint work (including ancestor repositioning).
/// The callback merely queues a coalesced post-frame measurement.
class _AnchorLayoutObserver extends SingleChildRenderObjectWidget {
  const _AnchorLayoutObserver({required this.onChanged, required super.child});

  final VoidCallback onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchorLayoutObserver(onChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAnchorLayoutObserver renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderAnchorLayoutObserver extends RenderProxyBox {
  _RenderAnchorLayoutObserver(this.onChanged);

  VoidCallback onChanged;

  @override
  void performLayout() {
    super.performLayout();
    onChanged();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onChanged();
  }
}
