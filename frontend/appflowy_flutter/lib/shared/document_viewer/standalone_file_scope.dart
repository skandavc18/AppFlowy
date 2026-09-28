import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef StandaloneFileToolbarBuilder = Widget Function(
  BuildContext context,
  Widget fileActions,
);

/// Renderer-owned controls offered to a standalone file's identity row.
/// No controller, document or persistence is transferred to the host.
class StandaloneFileHeader {
  const StandaloneFileHeader({
    this.actions = const [],
    this.toolbar,
    this.toolbarBuilder,
    this.responsiveToolbar = false,
    this.leading,
    this.keepActionsVisible = false,
  });

  final List<Widget> actions;
  final Widget? toolbar;

  /// Laid out at the host's actual width, with original-file actions in the
  /// same control group. The renderer itself remains in its original subtree.
  final StandaloneFileToolbarBuilder? toolbarBuilder;
  final bool responsiveToolbar;
  final Widget? leading;
  final bool keepActionsVisible;
}

/// Measures the actual tools before giving the remaining width to identity.
///
/// Unlike a percentage-sized toolbar slot, loose measurement lets a renderer's
/// Wrap hug its controls. The measured group is then placed at the content's
/// physical-right gutter. If the title would be squeezed, tools move below it using
/// the same render children: no breakpoint reparenting, scrolling or clipping.
/// Like the standalone pane it serves, this layout requires a bounded width.
class StandaloneFileHeaderLayout extends MultiChildRenderObjectWidget {
  StandaloneFileHeaderLayout({
    super.key,
    required Widget identity,
    required Widget tools,
  }) : super(children: [identity, tools]);

  // Reserve the icon/gap and a readable, text-scaled filename before wrapping.
  // This is a minimum title allowance, not a maximum reading/toolbar width.
  double _minimumIdentityWidth(BuildContext context) =>
      38 + MediaQuery.textScalerOf(context).scale(160);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStandaloneFileHeader(
        minimumIdentityWidth: _minimumIdentityWidth(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) {
    (renderObject as _RenderStandaloneFileHeader).minimumIdentityWidth =
        _minimumIdentityWidth(context);
  }
}

class _StandaloneFileHeaderParentData
    extends ContainerBoxParentData<RenderBox> {}

class _RenderStandaloneFileHeader extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StandaloneFileHeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox,
            _StandaloneFileHeaderParentData> {
  _RenderStandaloneFileHeader({
    required double minimumIdentityWidth,
  }) : _minimumIdentityWidth = minimumIdentityWidth;

  static const _spacing = 12.0;
  static const _runSpacing = 4.0;
  double _minimumIdentityWidth;

  set minimumIdentityWidth(double value) {
    if (_minimumIdentityWidth == value) return;
    _minimumIdentityWidth = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StandaloneFileHeaderParentData) {
      child.parentData = _StandaloneFileHeaderParentData();
    }
  }

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth);
    final identity = firstChild!;
    final tools = lastChild!;
    final width = constraints.maxWidth;
    // LayoutBuilder-based toolbars cannot be measured with intrinsic sizing.
    // Lay out the real group once, allowing its own Wrap to use the full pane.
    tools.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final remaining = math.max(0.0, width - tools.size.width - _spacing);
    final stacked = remaining < _minimumIdentityWidth;
    identity.layout(
      BoxConstraints.tightFor(width: stacked ? width : remaining),
      parentUsesSize: true,
    );
    final height = stacked
        ? identity.size.height + _runSpacing + tools.size.height
        : math.max(identity.size.height, tools.size.height);
    size = constraints.constrain(Size(width, height));
    (identity.parentData! as _StandaloneFileHeaderParentData).offset = Offset(
      0,
      stacked ? 0 : (height - identity.size.height) / 2,
    );
    (tools.parentData! as _StandaloneFileHeaderParentData).offset = Offset(
      width - tools.size.width,
      stacked
          ? identity.size.height + _runSpacing
          : (height - tools.size.height) / 2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A presentation-only slot. Publishing is deferred until after the frame so
/// a descendant header never dirties its host during build/layout. The identity
/// row stays mounted even while a renderer is loading or being rebound.
class StandaloneFileChromeController
    extends ValueNotifier<StandaloneFileHeader> {
  StandaloneFileChromeController() : super(const StandaloneFileHeader());

  Object? _owner;
  StandaloneFileHeader _pending = const StandaloneFileHeader();
  bool _scheduled = false;
  bool _disposed = false;

  void _publish(Object owner, StandaloneFileHeader controls) {
    if (_disposed) return;
    _owner = owner;
    _pending = controls;
    _schedule();
  }

  void _withdraw(Object owner) {
    if (_disposed || !identical(owner, _owner)) return;
    _owner = null;
    _pending = const StandaloneFileHeader();
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) value = _pending;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    _owner = null;
    _pending = const StandaloneFileHeader();
    super.dispose();
  }
}

/// Replaces only a renderer's duplicate header, never its content subtree.
class StandaloneFileHeaderSlot extends StatefulWidget {
  const StandaloneFileHeaderSlot({
    super.key,
    required this.controller,
    required this.controls,
  });

  final StandaloneFileChromeController controller;
  final StandaloneFileHeader controls;

  @override
  State<StandaloneFileHeaderSlot> createState() =>
      _StandaloneFileHeaderSlotState();
}

class _StandaloneFileHeaderSlotState extends State<StandaloneFileHeaderSlot> {
  @override
  void didUpdateWidget(covariant StandaloneFileHeaderSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._withdraw(this);
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.controller._publish(this, widget.controls);
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    widget.controller._withdraw(this);
    super.dispose();
  }
}

/// An opt-in presentation boundary for a file opened as a workspace page.
///
/// Embedded previews never install this scope. The renderer keeps the name it
/// was opened with (renaming a view must not reload a file/draft); the host owns
/// its live, editable identity. Matching the original name prevents an archive
/// entry's header from accidentally adopting the enclosing archive's identity.
class StandaloneFileScope extends InheritedWidget {
  const StandaloneFileScope({
    super.key,
    required this.canvas,
    required this.rendererName,
    required this.displayName,
    required this.chrome,
    required this.canEdit,
    required this.canRead,
    required this.editable,
    required this.available,
    this.metadata,
    required super.child,
  });

  final Color canvas;
  final String rendererName;
  final String displayName;
  final StandaloneFileChromeController chrome;

  /// Checked at activation too, not just while painting a disabled control.
  final bool Function() canEdit;
  final bool Function() canRead;
  final bool editable;
  final bool available;

  /// Live viewer settings, separate from the immutable file/loader identity.
  final Map<String, dynamic>? metadata;

  static StandaloneFileScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StandaloneFileScope>();

  static StandaloneFileScope? forName(BuildContext context, String? name) {
    final scope = maybeOf(context);
    return scope?.rendererName == name ? scope : null;
  }

  @override
  bool updateShouldNotify(StandaloneFileScope oldWidget) =>
      canvas != oldWidget.canvas ||
      rendererName != oldWidget.rendererName ||
      displayName != oldWidget.displayName ||
      chrome != oldWidget.chrome ||
      metadata != oldWidget.metadata ||
      editable != oldWidget.editable ||
      available != oldWidget.available;
}
