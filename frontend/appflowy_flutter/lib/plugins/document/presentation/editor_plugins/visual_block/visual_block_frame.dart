import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'visual_block_style.dart';

/// The card every visual block is drawn on.
///
/// It owns the whole of the shared behaviour — the quiet header, the controls
/// that fade in under the pointer, the one three-dot menu, the focus ring and
/// the accessible name — so a diagram, a mind map, an equation and a drawing
/// are the same kind of object with different contents.
class VisualBlockFrame extends StatefulWidget {
  const VisualBlockFrame({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.menuBuilder,
    this.headerActions = const <Widget>[],
    this.showHeader = true,
    this.onActivate,
    this.padding = EdgeInsets.zero,
    this.background,
    this.footer,
    this.semanticsHint,
    this.focusNode,
  });

  final IconData icon;

  /// Named in the header and read out by a screen reader.
  final String title;
  final Widget child;

  /// The rows of the shared three-dot menu. Absent means no menu is offered.
  final List<AppMenuEntry> Function(BuildContext context)? menuBuilder;

  /// Small controls shown before the three-dot button. They fade in with the
  /// pointer rather than sitting on the page permanently.
  final List<Widget> headerActions;

  final bool showHeader;

  /// Run when the body is clicked or Enter is pressed with the block focused.
  final VoidCallback? onActivate;

  final EdgeInsets padding;
  final Color? background;
  final Widget? footer;

  /// A sentence added after the title for a screen reader — "3 nodes",
  /// "flowchart", "12 shapes".
  final String? semanticsHint;

  final FocusNode? focusNode;

  @override
  State<VisualBlockFrame> createState() => _VisualBlockFrameState();
}

class _VisualBlockFrameState extends State<VisualBlockFrame> {
  bool _hovered = false;
  bool _focused = false;
  bool _menuOpen = false;

  bool get _controlsVisible => _hovered || _focused || _menuOpen;

  Future<void> _openMenu(BuildContext context, Offset position) async {
    final builder = widget.menuBuilder;
    if (builder == null) {
      return;
    }
    setState(() => _menuOpen = true);
    await showAppMenu<Object?>(
      context: context,
      entries: builder(context),
      globalPosition: position,
    );
    if (mounted) {
      setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showHeader) _buildHeader(context, palette),
        Flexible(child: Padding(padding: widget.padding, child: widget.child)),
        if (widget.footer != null) widget.footer!,
      ],
    );

    body = ViewerCard(
      color: widget.background ?? palette.surface,
      borderRadius: BorderRadius.circular(VisualBlockMetrics.cardRadius),
      elevation: _controlsVisible
          ? ViewerCardElevation.raised
          : ViewerCardElevation.resting,
      reactsToPointer: false,
      child: body,
    );

    if (_focused) {
      body = Container(
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(VisualBlockMetrics.cardRadius + 3),
          border: Border.all(
            color: palette.accent.withValues(alpha: 0.55),
            width: 1.6,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: body,
      );
    } else {
      body = Padding(padding: const EdgeInsets.all(2), child: body);
    }

    return Semantics(
      container: true,
      label: widget.semanticsHint == null
          ? widget.title
          : '${widget.title}. ${widget.semanticsHint}',
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter &&
              widget.onActivate != null) {
            widget.onActivate!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          opaque: false,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onSecondaryTapDown: widget.menuBuilder == null
                ? null
                : (details) =>
                    unawaited(_openMenu(context, details.globalPosition)),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, VisualBlockPalette palette) {
    return SizedBox(
      height: VisualBlockMetrics.headerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
        child: Row(
          children: [
            Icon(widget.icon, size: 14, color: palette.textMuted),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: palette.textMuted,
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: VisualBlockMetrics.hover,
              curve: VisualBlockMetrics.curve,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...widget.headerActions,
                    if (widget.menuBuilder != null)
                      Builder(
                        builder: (buttonContext) => VisualBlockButton(
                          icon: Icons.more_horiz_rounded,
                          tooltip: LocaleKeys.document_plugins_optionAction_more
                              .tr(),
                          palette: palette,
                          selected: _menuOpen,
                          onTap: () {
                            final box =
                                buttonContext.findRenderObject() as RenderBox?;
                            final origin = box == null
                                ? Offset.zero
                                : box.localToGlobal(
                                    Offset(0, box.size.height + 4),
                                  );
                            unawaited(_openMenu(buttonContext, origin));
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
