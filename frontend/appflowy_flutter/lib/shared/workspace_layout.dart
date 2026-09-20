import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Constraint-only workspace geometry, in logical pixels. These calculations
/// never write preferences or use physical screen size/device pixel ratio.
abstract final class WorkspaceLayout {
  static const sidebarBreakpoint = 1024.0;
  static const minimumContentWidth = 320.0;
  static const minimumSidebarWidth = 260.0;
  static const drawerEdge = 32.0;
  static const headerBreakpoint = 840.0;

  static double finiteExtent(double value, {double fallback = 0}) {
    if (value.isFinite) return math.max(0.0, value);
    return fallback.isFinite ? math.max(0.0, fallback) : 0.0;
  }

  /// Prefer the pane over the window. A finite fallback is only needed by
  /// hosts such as a horizontal scroll view that do not bound their child.
  static double availableWidth(
    BoxConstraints constraints, {
    double fallbackWidth = headerBreakpoint,
  }) {
    if (constraints.hasBoundedWidth) {
      return finiteExtent(constraints.maxWidth);
    }
    return math.max(
      finiteExtent(constraints.minWidth),
      finiteExtent(fallbackWidth),
    );
  }

  static bool sidebarIsDrawer(double width) => width < sidebarBreakpoint;

  /// Bound a docked panel without modifying its remembered width.
  static double panelWidth({
    required double availableWidth,
    required double preferredWidth,
    double reservedWidth = minimumContentWidth,
  }) {
    final available = finiteExtent(availableWidth);
    return math.min(
      finiteExtent(preferredWidth),
      math.max(0.0, available - finiteExtent(reservedWidth)),
    );
  }
}

@immutable
class WorkspaceDocumentGeometry {
  const WorkspaceDocumentGeometry._({
    required this.pageWidth,
    required this.outerInset,
    required this.contentLeft,
    required this.contentRight,
    required this.actionGutterWidth,
  });

  factory WorkspaceDocumentGeometry.resolve({
    required double availableWidth,
    required double preferredMaxWidth,
    required double actionGutterWidth,
  }) {
    final available = WorkspaceLayout.finiteExtent(
      availableWidth,
      fallback: preferredMaxWidth,
    );
    final maximum = preferredMaxWidth.isFinite && preferredMaxWidth > 0
        ? preferredMaxWidth
        : available;
    final pageWidth = math.min(available, maximum);
    final gutter = WorkspaceLayout.finiteExtent(actionGutterWidth);
    // Collapse spare whitespace, not the block action buttons. At ordinary
    // desktop widths both content edges have the same 64..96px inset.
    final inset = (pageWidth * 0.1).clamp(64.0, 96.0).toDouble();
    final left = math.min(pageWidth, math.max(gutter, inset));
    final right = math.min(left, math.max(0.0, pageWidth - left));
    return WorkspaceDocumentGeometry._(
      pageWidth: pageWidth,
      outerInset: (available - pageWidth) / 2,
      contentLeft: left,
      contentRight: right,
      actionGutterWidth: gutter,
    );
  }

  /// The saved maximum includes margins, as it did before responsive layout.
  final double pageWidth;
  final double outerInset;
  final double contentLeft;
  final double contentRight;
  final double actionGutterWidth;

  double get contentWidth =>
      math.max(0.0, pageWidth - contentLeft - contentRight);

  EdgeInsets get editorPadding => EdgeInsets.only(
        left: math.max(0.0, contentLeft - actionGutterWidth),
        right: contentRight,
      );

  EdgeInsets editorPaddingFor(TextDirection direction) =>
      direction == TextDirection.rtl ? editorPadding.flipped : editorPadding;

  EdgeInsets get headerPadding =>
      EdgeInsets.only(left: contentLeft, right: contentRight);
}

@immutable
class WorkspaceShellGeometry {
  const WorkspaceShellGeometry._({
    required this.availableWidth,
    required this.sidebarWidth,
    required this.sidebarIsDrawer,
    required this.editPanelWidth,
    required this.contentLeft,
    required this.contentRight,
  });

  factory WorkspaceShellGeometry.resolve({
    required double availableWidth,
    required double preferredSidebarWidth,
    required bool showSidebar,
    required bool showEditPanel,
    required double preferredEditPanelWidth,
  }) {
    final available = WorkspaceLayout.finiteExtent(availableWidth);
    final drawer = WorkspaceLayout.sidebarIsDrawer(available);
    final panel = WorkspaceLayout.panelWidth(
      availableWidth: available,
      preferredWidth: preferredEditPanelWidth,
      reservedWidth: drawer
          ? WorkspaceLayout.drawerEdge
          : WorkspaceLayout.minimumContentWidth,
    );
    // On a narrow window the existing positioned panel overlays the page;
    // it must not reduce that page to zero or reparent its editor.
    final right = showEditPanel && !drawer ? panel : 0.0;
    final sidebar = WorkspaceLayout.panelWidth(
      availableWidth: available - right,
      preferredWidth: math.max(
        WorkspaceLayout.minimumSidebarWidth,
        WorkspaceLayout.finiteExtent(preferredSidebarWidth),
      ),
      reservedWidth: drawer
          ? WorkspaceLayout.drawerEdge
          : WorkspaceLayout.minimumContentWidth,
    );
    return WorkspaceShellGeometry._(
      availableWidth: available,
      sidebarWidth: sidebar,
      sidebarIsDrawer: drawer,
      editPanelWidth: panel,
      contentLeft: showSidebar && !drawer ? sidebar : 0.0,
      contentRight: right,
    );
  }

  final double availableWidth;
  final double sidebarWidth;
  final bool sidebarIsDrawer;
  final double editPanelWidth;
  final double contentLeft;
  final double contentRight;

  double get contentWidth =>
      math.max(0.0, availableWidth - contentLeft - contentRight);
}

@immutable
class WorkspaceHeaderGeometry {
  const WorkspaceHeaderGeometry._({
    required this.width,
    required this.stacked,
    required this.identityWidth,
    required this.actionsWidth,
  });

  factory WorkspaceHeaderGeometry.resolve({
    required double availableWidth,
    double textScale = 1,
  }) {
    final width = WorkspaceLayout.finiteExtent(availableWidth);
    final scale = math.max(
      1.0,
      WorkspaceLayout.finiteExtent(textScale, fallback: 1),
    );
    final stacked = width < WorkspaceLayout.headerBreakpoint * scale;
    final actions = stacked ? width : math.min(width * 0.5, 480.0 * scale);
    return WorkspaceHeaderGeometry._(
      width: width,
      stacked: stacked,
      identityWidth: stacked ? width : math.max(0.0, width - actions - gap),
      actionsWidth: actions,
    );
  }

  static const gap = 24.0;
  static const runGap = 12.0;

  final double width;
  final bool stacked;
  final double identityWidth;
  final double actionsWidth;
}
