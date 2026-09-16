import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'document_viewport_style.dart';

/// What the fixed header says about the open document.
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
/// surface it sits on: a fixed header, an optional docked toolbar and consistent
/// spacing, so switching file types never feels like
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

  /// An optional bottom toolbar, docked outside the document's viewport.
  /// The original parameter name is retained for existing callers.
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
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final surfaceColor = widget.background ?? style.canvas;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DocumentViewportHeader(
          identity: widget.identity,
          actions: widget.actions,
          leading: widget.leading,
          background: surfaceColor,
        ),
        Expanded(
          child: ClipRect(
            child: FadeTransition(
              opacity: reducedMotion
                  ? const AlwaysStoppedAnimation(1.0)
                  : reveal.drive(CurveTween(curve: AppFlowyMotion.enterCurve)),
              child: RepaintBoundary(child: widget.child),
            ),
          ),
        ),
        if (widget.floatingToolbar != null) widget.floatingToolbar!,
      ],
    );

    final surface = ColoredBox(
      color: surfaceColor,
      child: content,
    );
    return widget.framed
        ? ViewerCard(
            borderRadius: DocumentViewportStyle.borderRadius,
            child: surface,
          )
        : surface;
  }
}

/// A workspace-aligned toolbar, separated by space rather than a drawn rule.
/// Its fill can match the renderer; depth and blur belong to menus, not chrome.
class DocumentViewportBar extends StatelessWidget {
  const DocumentViewportBar({
    super.key,
    required this.child,
    this.background,
    this.padding = const EdgeInsets.symmetric(
      horizontal: DocumentViewportStyle.horizontalPadding,
      vertical: 6,
    ),
  });

  final Widget child;
  final Color? background;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    return Container(
      constraints: const BoxConstraints(
        minHeight: DocumentViewportStyle.headerHeight,
      ),
      padding: padding,
      color: background ?? style.chrome,
      child: child,
    );
  }
}

/// Fixed identity and tools. A larger tool set shares the row when there is
/// room, and wraps below the identity in a compact pane without reparenting it.
class DocumentViewportHeader extends StatelessWidget {
  const DocumentViewportHeader({
    super.key,
    required this.identity,
    this.actions = const [],
    this.showActions = true,
    this.leading,
    this.toolbar,
    this.background,
  });

  final DocumentIdentity identity;
  final List<Widget> actions;

  /// Explicit visibility for hosts that need it; never driven by pointer hover.
  final bool showActions;

  final Widget? leading;

  /// A full control set, such as PDF navigation, zoom and document actions.
  final Widget? toolbar;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    final subtitle = identity.subtitle;
    final face = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    return DocumentViewportBar(
      background: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final stacked = available < DocumentViewportStyle.toolbarBreakpoint ||
              MediaQuery.textScalerOf(context).scale(14) > 20;
          final toolbarWidth =
              stacked ? available : (available * 0.68).clamp(0.0, 780.0);
          final identityWidth = toolbar == null || stacked
              ? available
              : available - toolbarWidth - 16;

          return Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: identityWidth,
                child: Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 4),
                    ],
                    Icon(identity.icon, size: 18, color: style.icon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Tooltip(
                            message: identity.title,
                            child: Text(
                              identity.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: face.copyWith(
                                fontSize: 13,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                fontVariations: const [
                                  FontVariation.weight(600),
                                ],
                                letterSpacing: -0.1,
                                color: style.textPrimary,
                              ),
                            ),
                          ),
                          if (subtitle != null && subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: face.copyWith(
                                fontSize: 11,
                                height: 1.3,
                                fontWeight: FontWeight.w400,
                                fontVariations: const [
                                  FontVariation.weight(450),
                                ],
                                color: style.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Visibility(
                        visible: showActions,
                        maintainState: true,
                        maintainAnimation: true,
                        maintainSize: true,
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: identityWidth * 0.55),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (toolbar != null)
                SizedBox(width: toolbarWidth, child: toolbar!),
            ],
          );
        },
      ),
    );
  }
}

/// A docked control cluster. The original name is retained for existing hosts.
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
    return Container(
      color: style.chrome,
      padding: padding,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
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

/// Whitespace between toolbar groups, without a vertical rule.
class DocumentViewportSeparator extends StatelessWidget {
  const DocumentViewportSeparator({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 12);
}

/// A legible, one-click fit action instead of another ambiguous fullscreen
/// glyph. Optional choices sit beside it without changing the primary action.
class DocumentViewportFitButton extends StatelessWidget {
  const DocumentViewportFitButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Fit to view',
    this.options,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final Widget? options;

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    final foreground = WidgetStateProperty.resolveWith<Color>(
      (states) =>
          states.contains(WidgetState.disabled) ? style.iconMuted : style.icon,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tooltip,
          child: TextButton(
            onPressed: onPressed,
            style: WorkspaceChrome.controlStyle(context).copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              foregroundColor: foreground,
              iconColor: foreground,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (context) => CustomPaint(
                    key: const ValueKey('document-fit-glyph'),
                    size: const Size.square(18),
                    painter: _FitViewGlyph(
                      IconTheme.of(context).color ?? style.icon,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('Fit'),
              ],
            ),
          ),
        ),
        if (options != null) options!,
      ],
    );
  }
}

/// Rounded viewport corners and a light content outline, not a filled monitor.
class _FitViewGlyph extends CustomPainter {
  const _FitViewGlyph(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(size.width / 20, size.height / 20);
    final corners = Path()
      ..moveTo(2, 6)
      ..lineTo(2, 3.5)
      ..quadraticBezierTo(2, 2, 3.5, 2)
      ..lineTo(6, 2)
      ..moveTo(14, 2)
      ..lineTo(16.5, 2)
      ..quadraticBezierTo(18, 2, 18, 3.5)
      ..lineTo(18, 6)
      ..moveTo(18, 14)
      ..lineTo(18, 16.5)
      ..quadraticBezierTo(18, 18, 16.5, 18)
      ..lineTo(14, 18)
      ..moveTo(6, 18)
      ..lineTo(3.5, 18)
      ..quadraticBezierTo(2, 18, 2, 16.5)
      ..lineTo(2, 14);
    canvas.drawPath(corners, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 6, 8, 8),
        const Radius.circular(1.5),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FitViewGlyph oldDelegate) => oldDelegate.color != color;
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
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    final enabled = widget.onPressed != null;
    final background = !enabled
        ? style.control
        : pressing || widget.selected
            ? style.controlActive
            : hovering || focused
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
        selected: widget.selected,
        label: widget.tooltip,
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onShowFocusHighlight: (value) => setState(() => focused = value),
          onShowHoverHighlight: (value) => setState(() {
            hovering = value;
            if (!value) pressing = false;
          }),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => pressing = true) : null,
            onTapUp: enabled ? (_) => setState(() => pressing = false) : null,
            onTapCancel:
                enabled ? () => setState(() => pressing = false) : null,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppFlowyMotion.fast,
              curve: AppFlowyMotion.standardCurve,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: focused
                      ? style.accent
                      : style.accent.withValues(alpha: 0),
                ),
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
