import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/context_menu/custom_context_menu.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class BlockActionButton extends StatefulWidget {
  const BlockActionButton({
    super.key,
    required this.svg,
    required this.richMessage,
    required this.onTap,
    this.onSecondaryTap,
    this.showTooltip = true,
    this.onPointerDown,
  });

  final FlowySvgData svg;
  final bool showTooltip;
  final InlineSpan richMessage;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onPointerDown;

  @override
  State<BlockActionButton> createState() => _BlockActionButtonState();
}

class _BlockActionButtonState extends State<BlockActionButton> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return FlowyTooltip(
      richMessage: widget.showTooltip ? widget.richMessage : null,
      child: MouseRegion(
        cursor: Platform.isWindows
            ? SystemMouseCursors.click
            : SystemMouseCursors.grab,
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: isHovered
                ? Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Listener(
            onPointerDown: (event) {
              widget.onPointerDown?.call();
              if (event.buttons & kSecondaryMouseButton != 0) {
                EditorContextMenuRegion.preventForPointer(
                  context,
                  event.pointer,
                );
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTap: widget.onSecondaryTap ?? widget.onTap,
              child: FlowyIconButton(
                width: 28.0,
                radius: BorderRadius.circular(4.0),
                hoverColor: Colors.transparent,
                iconColorOnHover: Theme.of(context).iconTheme.color,
                onPressed: widget.onTap,
                icon: FlowySvg(
                  widget.svg,
                  size: const Size.square(21.0),
                  color: Theme.of(context).iconTheme.color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
