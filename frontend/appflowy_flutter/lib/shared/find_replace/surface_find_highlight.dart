import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';

import 'contextual_find.dart';
import 'find_highlight.dart';
import 'text_find.dart';

/// Opt-in operation accounting for isolated fixtures; never records text.
class SurfaceFindWork {
  @visibleForTesting
  static void Function(String)? onOperation;

  static void record(String operation) {
    assert(() {
      onOperation?.call(operation);
      return true;
    }());
  }
}

/// Paint-only highlighting for an explicitly owned piece of rendered text.
///
/// Keep this around text, never around page chrome or a collection of viewers.
/// It neither replaces spans nor changes selection, semantics, or hit testing.
/// Native views, nested targets and [SurfaceFindExclude] are opaque to it.
class SurfaceFindHighlight extends SingleChildRenderObjectWidget {
  const SurfaceFindHighlight({
    super.key,
    required super.child,
    required this.query,
    required this.options,
    this.currentOccurrence = -1,
    this.includeEditable = false,
    this.contentRoots,
    this.onGeometryChanged,
    this.canHighlight,
    this.canHighlightMatch,
  });

  final String query;
  final FindOptions options;
  final int currentOccurrence;
  final bool includeEditable;

  /// Explicit renderer-owned roots for a delegated, read-only embed. This is
  /// not permission to search a whole page or its configuration/chrome.
  final Iterable<RenderObject> Function()? contentRoots;
  final VoidCallback? onGeometryChanged;
  final bool Function(SurfaceFindTextRun)? canHighlight;

  /// Optional renderer-owned range gate (for example, an ellipsized preview).
  /// Rejected ranges consume no occurrence, keeping the index and paint aligned.
  final bool Function(SurfaceFindTextRun, RegExpMatch)? canHighlightMatch;

  /// A renderer-owned late mount/rebind behind a fixed-size repaint boundary.
  /// Signals membership only; the owner must still revalidate authorization.
  static void contentChanged(BuildContext context) {
    context.findAncestorRenderObjectOfType<RenderSurfaceFindHighlight>()?.contentChanged();
  }

  @override
  RenderSurfaceFindHighlight createRenderObject(BuildContext context) =>
      RenderSurfaceFindHighlight(excluded: () => _excludedSubtrees(context))
        ..contentRoots = contentRoots
        ..onGeometryChanged = onGeometryChanged
        ..canHighlight = canHighlight
        ..canHighlightMatch = canHighlightMatch
        ..configure(
          query,
          options,
          currentOccurrence,
          includeEditable,
          Theme.of(context).brightness,
        );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSurfaceFindHighlight renderObject,
  ) {
    renderObject._excluded = () => _excludedSubtrees(context);
    renderObject.contentRoots = contentRoots;
    renderObject.onGeometryChanged = onGeometryChanged;
    renderObject.canHighlight = canHighlight;
    renderObject.canHighlightMatch = canHighlightMatch;
    renderObject.configure(
      query,
      options,
      currentOccurrence,
      includeEditable,
      Theme.of(context).brightness,
    );
  }

  Set<RenderObject> _excludedSubtrees(BuildContext context) {
    final excluded = <RenderObject>{};
    if (!context.mounted) return excluded;
    final roots = contentRoots?.call().toSet() ?? const <RenderObject>{};
    bool containsRoot(RenderObject boundary) => roots.any((root) {
          for (RenderObject? object = root;
              object != null;
              object = object.parent) {
            if (identical(object, boundary)) return true;
          }
          return false;
        });
    void visit(Element element) {
      final widget = element.widget;
      if (widget is ContextualFindRegion ||
          widget is SurfaceFindHighlight ||
          (!includeEditable &&
              (widget is TextField || widget is EditableText)) ||
          (widget is EditableText && widget.obscureText)) {
        final render = element.findRenderObject();
        // Cross only the region that encloses an explicitly delegated root.
        // Nested viewers *inside* an editor remain separate owners.
        if (widget is ContextualFindRegion &&
            render != null &&
            containsRoot(render)) {
          element.visitChildElements(visit);
          return;
        }
        if (render != null) excluded.add(render);
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return excluded;
  }
}

/// An explicit boundary for content owned by another viewer.
class SurfaceFindExclude extends SingleChildRenderObjectWidget {
  const SurfaceFindExclude({super.key, required super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderSurfaceFindExclude();
}

class _RenderSurfaceFindExclude extends RenderProxyBox {}

/// A native paragraph segment. WidgetSpan placeholders retain their UTF-16
/// offset but their child paragraphs are visited in reading order, not lost.
class SurfaceFindTextRun {
  const SurfaceFindTextRun(this.render, this.text, this.start);
  final RenderBox render;
  final String text;
  final int start;

  List<TextBox> boxes(int from, int to) {
    final selection =
        TextSelection(baseOffset: start + from, extentOffset: start + to);
    final object = render;
    return object is RenderEditable
        ? object.getBoxesForSelection(selection)
        : (object as RenderParagraph).getBoxesForSelection(selection);
  }
}

/// paintsChild defaults to TRUE in Flutter 3.27.4. IndexedStack needs its
/// explicit index check; kept-alive sliver children still use paintsChild.
bool surfaceFindPaintsChild(RenderObject parent, RenderObject child) {
  if (!parent.paintsChild(child) ||
      (parent is RenderOffstage && parent.offstage) ||
      (parent is RenderOpacity && parent.opacity == 0) ||
      (parent is RenderAnimatedOpacity && parent.opacity.value == 0))
    return false;
  if (parent is RenderIndexedStack) {
    if (parent.index == null) return false;
    var displayed = parent.firstChild;
    for (var i = 0; i < parent.index! && displayed != null; i++) {
      displayed = parent.childAfter(displayed);
    }
    return identical(displayed, child);
  }
  return true;
}

bool surfaceFindRenderAvailable(RenderObject render) {
  if (!render.attached) return false;
  var child = render;
  for (var parent = child.parent; parent != null; parent = child.parent) {
    if (!parent.attached || !surfaceFindPaintsChild(parent, child))
      return false;
    child = parent;
  }
  return true;
}

List<SurfaceFindTextRun> surfaceFindTextRuns(
  RenderObject root, {
  bool includeEditable = false,
  Set<RenderObject> excluded = const {},
}) {
  SurfaceFindWork.record('textScan');
  final runs = <SurfaceFindTextRun>[];
  void visit(RenderObject object) {
    SurfaceFindWork.record('renderVisit');
    if (!object.attached ||
        excluded.contains(object) ||
        (object is RenderBox && !object.hasSize) ||
        object is RenderSurfaceFindHighlight ||
        object is _RenderSurfaceFindExclude ||
        object is PlatformViewRenderBox ||
        object is RenderUiKitView ||
        object is RenderAppKitView) return;
    if (object is RenderParagraph || object is RenderEditable) {
      if (object is RenderEditable && (!includeEditable || object.obscureText))
        return;
      final text = object is RenderParagraph
          ? object.text.toPlainText(includeSemanticsLabels: false)
          : (object as RenderEditable)
                  .text
                  ?.toPlainText(includeSemanticsLabels: false) ??
              '';
      final children = <RenderObject>[];
      object.visitChildren(children.add);
      var from = 0;
      var inline = 0;
      for (var index = 0; index < text.length; index++) {
        if (text.codeUnitAt(index) != 0xFFFC) continue;
        if (from < index)
          runs.add(SurfaceFindTextRun(
              object as RenderBox, text.substring(from, index), from));
        if (inline < children.length) {
          final child = children[inline++];
          if (surfaceFindPaintsChild(object, child)) visit(child);
        }
        from = index + 1;
      }
      if (from < text.length)
        runs.add(SurfaceFindTextRun(
            object as RenderBox, text.substring(from), from));
      return;
    }
    object.visitChildren((child) {
      if (surfaceFindPaintsChild(object, child)) visit(child);
    });
  }

  if (surfaceFindRenderAvailable(root)) visit(root);
  return runs;
}

class _HighlightBox {
  const _HighlightBox(this.owner, this.rect, this.occurrence);

  final RenderBox owner;
  final Rect rect;
  final int occurrence;
}

class RenderSurfaceFindHighlight extends RenderProxyBox {
  RenderSurfaceFindHighlight({Set<RenderObject> Function()? excluded})
      : _excluded = excluded;

  Set<RenderObject> Function()? _excluded;
  RegExp? _pattern;
  int _current = -1;
  bool _includeEditable = false;
  Brightness _brightness = Brightness.light;
  Iterable<RenderObject> Function()? contentRoots;
  VoidCallback? onGeometryChanged;
  bool Function(SurfaceFindTextRun)? canHighlight;
  bool Function(SurfaceFindTextRun, RegExpMatch)? canHighlightMatch;
  int _watchEpoch = 0;
  bool _watching = false;
  List<Object?>? _geometryStamp;

  void contentChanged() {
    _geometryStamp = null;
    _watch();
    if (_pattern != null) markNeedsPaint();
  }

  List<SurfaceFindTextRun> get textRuns {
    final roots = contentRoots?.call().toList() ?? [if (child != null) child!];
    final excluded = _excluded?.call() ?? const <RenderObject>{};
    return [
      for (final root in roots)
        ...surfaceFindTextRuns(root,
            includeEditable: _includeEditable, excluded: excluded),
    ];
  }

  void _watch() {
    if (_watching ||
        !attached ||
        (_pattern == null && onGeometryChanged == null)) return;
    _watching = true;
    final epoch = _watchEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (epoch != _watchEpoch) return;
      _watching = false;
      if (!attached) return;
      if (_pattern == null) {
        onGeometryChanged?.call();
        return;
      }
      if (!surfaceFindRenderAvailable(this)) return;
      final runs = textRuns;
      final stamp = <Object?>[
        for (final run in runs) ...[run.render, run.text, run.start],
        ..._boxes(runs).map(_localRect),
      ];
      if (!listEquals(stamp, _geometryStamp)) {
        _geometryStamp = stamp;
        markNeedsPaint();
        onGeometryChanged?.call();
      }
      // Quiescent renderers do no work on unrelated application frames.
      // Layout, paint and configuration restart this one-shot observation.
    });
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _watch();
  }

  @override
  void detach() {
    _watchEpoch++;
    _watching = false;
    _geometryStamp = null;
    super.detach();
  }

  void configure(
    String query,
    FindOptions options,
    int current,
    bool includeEditable,
    Brightness brightness,
  ) {
    try {
      _pattern = buildFindPattern(query, options);
    } on FormatException {
      _pattern = null;
    }
    _current = current;
    _includeEditable = includeEditable;
    _brightness = brightness;
    markNeedsPaint();
    _watch();
  }

  List<_HighlightBox> _boxes([List<SurfaceFindTextRun>? runs]) {
    final pattern = _pattern;
    if (pattern == null || !attached || !hasSize) return const [];
    final result = <_HighlightBox>[];
    var occurrence = 0;
    for (final run in runs ?? textRuns) {
      if (canHighlight?.call(run) == false) continue;
      for (final match in matchesOfPattern(run.text, pattern)) {
        if (canHighlightMatch?.call(run, match) == false) continue;
        for (final box in run.boxes(match.start, match.end)) {
          result.add(_HighlightBox(run.render, box.toRect(), occurrence));
        }
        occurrence++;
      }
    }
    return result;
  }

  Rect _localRect(_HighlightBox box) => MatrixUtils.transformRect(
        box.owner.getTransformTo(this),
        box.rect,
      );

  Rect _paintRect(_HighlightBox box) {
    var rect = _localRect(box);
    RenderObject child = box.owner;
    for (var parent = child.parent;
        parent != null && child != this;
        parent = child.parent) {
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        rect = rect.intersect(
            MatrixUtils.transformRect(parent.getTransformTo(this), clip));
      }
      child = parent;
    }
    return rect;
  }

  /// Actual laid-out word geometry, also useful to verify non-golden tests.
  List<Rect> get matchRects => _boxes().map(_localRect).toList();

  Rect? get currentRect {
    Rect? result;
    for (final box in _boxes().where((box) => box.occurrence == _current)) {
      final rect = _localRect(box);
      result = result?.expandToInclude(rect) ?? rect;
    }
    return result;
  }

  /// Uses native scrolling, including the viewport inside a TextField. No
  /// selection/caret mutation is needed to reveal a match in a read-only field.
  void revealCurrent() {
    final boxes = _boxes().where((box) => box.occurrence == _current);
    if (boxes.isEmpty) return;
    _HighlightBox combined(Iterable<_HighlightBox> boxes) => _HighlightBox(
          boxes.first.owner,
          boxes.map((box) => box.rect).reduce((a, b) => a.expandToInclude(b)),
          _current,
        );
    var first = combined(boxes);
    final editable = first.owner;
    if (editable is RenderEditable && editable.maxScrollExtent > 0) {
      // RenderEditable owns a ViewportOffset rather than a RenderViewport;
      // showOnScreen alone only scrolls its ancestors in Flutter 3.27.
      final vertical = editable.maxLines != 1;
      final extent = vertical ? editable.size.height : editable.size.width;
      final leading = vertical ? first.rect.top : first.rect.left;
      final trailing = vertical ? first.rect.bottom : first.rect.right;
      final delta = leading < 0
          ? leading - 8
          : trailing > extent
              ? trailing - extent + 8
              : 0.0;
      if (delta != 0) {
        editable.offset.jumpTo(
          (editable.offset.pixels + delta).clamp(0.0, editable.maxScrollExtent),
        );
        final updated = _boxes().where((box) => box.occurrence == _current);
        if (updated.isEmpty) return;
        first = combined(updated);
      }
    }
    first.owner.showOnScreen(
      rect: first.rect.inflate(8),
    );
  }

  @override
  void performLayout() {
    super.performLayout();
    _watch();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _watch();
    if (_pattern == null) return;
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);
    for (final box in _boxes()) {
      final rect = _paintRect(box).shift(offset);
      if (!rect.isFinite || rect.isEmpty) continue;
      final current = box.occurrence == _current;
      final color = current
          ? FindHighlightColors.current(_brightness)
          : FindHighlightColors.match(_brightness);
      // This is above the original glyphs, not an opaque background replacing
      // them. Low alpha keeps styled code and paper-mode ink readable.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = color.withValues(alpha: current ? 0.30 : 0.19),
      );
      if (current) {
        canvas.drawLine(
          rect.bottomLeft,
          rect.bottomRight,
          Paint()
            ..color = color
            ..strokeWidth = 1,
        );
      }
    }
    canvas.restore();
  }
}
