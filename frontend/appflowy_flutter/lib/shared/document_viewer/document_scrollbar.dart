import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'document_viewer_theme.dart';

/// A thin, rounded overlay scrollbar shared by every document renderer.
///
/// It never occupies layout space, fades in while the document moves and
/// fades out again once it settles. Hovering the gutter thickens the thumb
/// slightly so it becomes an easy drag target without ever shifting content.
class DocumentScrollbar extends StatefulWidget {
  const DocumentScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.notificationPredicate,
  });

  final ScrollController? controller;
  final Widget child;

  /// Insets the thumb so it clears floating chrome.
  final EdgeInsets padding;
  final ScrollNotificationPredicate? notificationPredicate;

  /// Resting thumb thickness in logical pixels.
  static const double thickness = 6;

  /// Thickness while the pointer rests in the gutter.
  static const double hoveredThickness = 9;

  /// Width of the invisible hover target along the trailing edge.
  static const double gutterWidth = 22;

  static const Duration fadeDuration = AppFlowyMotion.deliberate;
  static const Duration timeToFade = Duration(milliseconds: 900);

  @override
  State<DocumentScrollbar> createState() => _DocumentScrollbarState();
}

class _DocumentScrollbarState extends State<DocumentScrollbar> {
  bool gutterHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final thickness = gutterHovered
        ? DocumentScrollbar.hoveredThickness
        : DocumentScrollbar.thickness;

    return MouseRegion(
      opaque: false,
      onHover: _handleHover,
      onExit: (_) => _setGutterHovered(false),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: thickness),
        duration: AppFlowyMotion.fast,
        curve: AppFlowyMotion.standardCurve,
        builder: (context, value, child) => RawScrollbar(
          controller: widget.controller,
          thumbColor: theme.scrollThumb,
          thickness: value,
          radius: Radius.circular(value / 2),
          minThumbLength: 42,
          mainAxisMargin: 6,
          crossAxisMargin: 4,
          padding: widget.padding,
          interactive: true,
          fadeDuration: DocumentScrollbar.fadeDuration,
          timeToFade: DocumentScrollbar.timeToFade,
          notificationPredicate: widget.notificationPredicate ??
              defaultScrollNotificationPredicate,
          child: child!,
        ),
        child: widget.child,
      ),
    );
  }

  void _handleHover(PointerHoverEvent event) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }
    final local = box.globalToLocal(event.position);
    final distanceFromTrailingEdge = box.size.width - local.dx;
    _setGutterHovered(
      distanceFromTrailingEdge >= 0 &&
          distanceFromTrailingEdge <= DocumentScrollbar.gutterWidth,
    );
  }

  void _setGutterHovered(bool value) {
    if (gutterHovered == value) {
      return;
    }
    setState(() => gutterHovered = value);
  }
}
