import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

import 'editor_surface_style.dart';

/// How high a [ViewerCard] sits above the page.
enum ViewerCardElevation {
  /// Flush with the page. For a card nested inside another card, where a
  /// second shadow would only muddy the first.
  flush,

  /// The resting state of every document card.
  resting,

  /// Held at the hover height regardless of the pointer, for a card that is
  /// the focus of the screen — a fullscreen viewer, say.
  raised,
}

/// The one card every document viewer lives in.
///
/// PDF shells, code blocks, Markdown and HTML previews, pictures, media
/// players and embedded documents all use this, so a document reads as the
/// same kind of object wherever it appears.
///
/// It has no outline. Depth comes entirely from
/// [EditorSurfaceStyle.embedShadow], which lifts a little further while the
/// pointer rests on the card or something inside it holds focus — a change of
/// height, never of character, over [AppFlowyMotion.gentle].
class ViewerCard extends StatefulWidget {
  const ViewerCard({
    super.key,
    required this.child,
    this.color,
    this.borderRadius,
    this.clipBehavior = Clip.antiAlias,
    this.elevation = ViewerCardElevation.resting,
    this.reactsToPointer = true,
  });

  final Widget child;

  /// The card surface. Left null for a card whose content paints its own
  /// background edge to edge, such as a photograph.
  final Color? color;

  /// Defaults to [EditorSurfaceStyle.embedBorderRadius], the radius shared by
  /// every embedded document.
  final BorderRadius? borderRadius;

  final Clip clipBehavior;

  final ViewerCardElevation elevation;

  /// Whether hover and focus lift the card. Turned off for cards that are
  /// already inside an interactive surface, where a second reaction to the
  /// same pointer reads as noise.
  final bool reactsToPointer;

  @override
  State<ViewerCard> createState() => _ViewerCardState();
}

class _ViewerCardState extends State<ViewerCard> {
  bool hovered = false;
  bool focused = false;

  bool get _isRaised =>
      widget.elevation == ViewerCardElevation.raised ||
      (widget.reactsToPointer &&
          widget.elevation != ViewerCardElevation.flush &&
          (hovered || focused));

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? EditorSurfaceStyle.embedBorderRadius;
    Widget card = AnimatedContainer(
      duration: AppFlowyMotion.gentle,
      curve: AppFlowyMotion.standardCurve,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: radius,
        boxShadow: widget.elevation == ViewerCardElevation.flush
            ? const []
            : EditorSurfaceStyle.embedShadow(context, raised: _isRaised),
      ),
      // A rounded-rect clip rather than the container's own path clip: PDF
      // pages and WebView textures are redrawn constantly and cannot afford
      // the more expensive shape.
      child: widget.clipBehavior == Clip.none
          ? widget.child
          : ClipRRect(
              borderRadius: radius,
              clipBehavior: widget.clipBehavior,
              child: widget.child,
            ),
    );

    if (!widget.reactsToPointer ||
        widget.elevation != ViewerCardElevation.resting) {
      return card;
    }

    // The focus node neither takes focus nor joins the traversal order: it is
    // here only to hear when something inside the card starts editing.
    card = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) {
        if (mounted && value != focused) {
          setState(() => focused = value);
        }
      },
      child: card,
    );

    return MouseRegion(
      opaque: false,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: card,
    );
  }

  void _setHovered(bool value) {
    if (mounted && value != hovered) {
      setState(() => hovered = value);
    }
  }
}
