import 'dart:ui' as ui;

import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

import 'document_viewport_style.dart';

/// What the floating header says about the open document.
@immutable
class DocumentIdentity {
  const DocumentIdentity({
    required this.title,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final IconData icon;

  /// Quiet metadata: file type, size, page count — whatever the renderer knows.
  final String? subtitle;
}

/// The shared chrome that surrounds every document renderer.
///
/// The renderer passed as [child] is never inspected or restyled — it keeps
/// full responsibility for drawing the document. This widget only supplies the
/// surface it sits on: a floating header, an optional floating toolbar, soft
/// depth and consistent spacing, so switching file types never feels like
/// switching applications.
class DocumentViewport extends StatefulWidget {
  const DocumentViewport({
    super.key,
    required this.identity,
    required this.child,
    this.actions = const [],
    this.floatingToolbar,
    this.leading,
    this.background,
    this.framed = true,
    this.revealKey,
  });

  final DocumentIdentity identity;

  /// The document renderer, mounted verbatim.
  final Widget child;

  /// Small controls aligned to the trailing edge of the header.
  final List<Widget> actions;

  /// An optional control cluster floating over the bottom of the document.
  final Widget? floatingToolbar;

  final Widget? leading;

  /// Overrides the surface behind the renderer. Media uses this for black.
  final Color? background;

  /// Draws the outer card. Disabled when a host already frames the viewport.
  final bool framed;

  /// Changing this cross-fades to a different document.
  final Object? revealKey;

  @override
  State<DocumentViewport> createState() => _DocumentViewportState();
}

class _DocumentViewportState extends State<DocumentViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController reveal = AnimationController(
    vsync: this,
    duration: AppFlowyMotion.deliberate,
  )..forward();

  @override
  void didUpdateWidget(covariant DocumentViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealKey != widget.revealKey) {
      reveal
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);

    final content = Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(
              top: DocumentViewportStyle.contentTopInset,
            ),
            child: RepaintBoundary(child: widget.child),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: DocumentViewportHeader(
            identity: widget.identity,
            actions: widget.actions,
            leading: widget.leading,
          ),
        ),
        if (widget.floatingToolbar != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: widget.floatingToolbar,
            ),
          ),
      ],
    );

    final surface = ColoredBox(
      color: widget.background ?? style.canvas,
      child: content,
    );

    final framed = widget.framed
        ? ViewerCard(
            borderRadius: DocumentViewportStyle.borderRadius,
            child: surface,
          )
        : surface;

    final curved = CurvedAnimation(
      parent: reveal,
      curve: AppFlowyMotion.enterCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.99, end: 1).animate(curved),
        child: framed,
      ),
    );
  }
}

/// The floating identity bar. No border, no ribbon — depth only.
class DocumentViewportHeader extends StatelessWidget {
  const DocumentViewportHeader({
    super.key,
    required this.identity,
    this.actions = const [],
    this.leading,
  });

  final DocumentIdentity identity;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    final subtitle = identity.subtitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DocumentViewportStyle.gutter,
        DocumentViewportStyle.gutter,
        DocumentViewportStyle.gutter,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: style.chromeShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: DocumentViewportStyle.blurSigma,
              sigmaY: DocumentViewportStyle.blurSigma,
            ),
            child: Container(
              height: DocumentViewportStyle.headerHeight -
                  DocumentViewportStyle.gutter,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: style.chrome,
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 4),
                  ],
                  Icon(identity.icon, size: 15, color: style.icon),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          identity.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: style.textPrimary,
                          ),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.3,
                              color: style.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A blurred control cluster that floats over the document.
class DocumentFloatingToolbar extends StatelessWidget {
  const DocumentFloatingToolbar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    final radius = BorderRadius.circular(12);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: style.chromeShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: DocumentViewportStyle.blurSigma,
            sigmaY: DocumentViewportStyle.blurSigma,
          ),
          child: Container(
            padding: padding,
            color: style.chrome,
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

/// Quiet metadata inside a toolbar — page counts, zoom levels.
class DocumentViewportLabel extends StatelessWidget {
  const DocumentViewportLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          color: style.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A hairline gap between toolbar groups.
class DocumentViewportSeparator extends StatelessWidget {
  const DocumentViewportSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: style.hairline,
    );
  }
}

/// The icon button used everywhere in the viewer chrome.
///
/// No ripple and no splash: a soft fill appears under the pointer and settles
/// within the standard motion window.
class DocumentViewportButton extends StatefulWidget {
  const DocumentViewportButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.accented = false,
    this.size = DocumentViewportStyle.controlSize,
    this.iconSize = DocumentViewportStyle.iconSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  /// Draws the glyph in the accent colour — used by the code run action.
  final bool accented;
  final double size;
  final double iconSize;

  @override
  State<DocumentViewportButton> createState() => _DocumentViewportButtonState();
}

class _DocumentViewportButtonState extends State<DocumentViewportButton> {
  bool hovering = false;
  bool pressing = false;

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    final enabled = widget.onPressed != null;
    final background = !enabled
        ? Colors.transparent
        : pressing || widget.selected
            ? style.controlActive
            : hovering
                ? style.controlHover
                : style.control;

    final foreground = !enabled
        ? style.iconMuted
        : widget.accented || widget.selected
            ? style.accent
            : style.icon;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 420),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => hovering = true),
          onExit: (_) => setState(() {
            hovering = false;
            pressing = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => pressing = true) : null,
            onTapUp: enabled ? (_) => setState(() => pressing = false) : null,
            onTapCancel:
                enabled ? () => setState(() => pressing = false) : null,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: AppFlowyMotion.fast,
              curve: AppFlowyMotion.standardCurve,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
