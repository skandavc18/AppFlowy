import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/context_menu/custom_context_menu.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
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

  /// The size of the square hit target of every block action button.
  static const double size = 28.0;

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
          duration:
              WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
          curve: WorkspaceTokens.curve,
          decoration: BoxDecoration(
            color: isHovered
                ? WorkspaceChrome.hoverColor(context)
                : WorkspaceChrome.hoverColor(context).withValues(alpha: 0),
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
                width: BlockActionButton.size,
                radius: BorderRadius.circular(4.0),
                hoverColor: Colors.transparent,
                iconColorOnHover: Theme.of(context).iconTheme.color,
                onPressed: widget.onTap,
                icon: WorkspaceGlyph.svg(
                  widget.svg,
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
