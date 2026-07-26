import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

import 'document_chrome.dart';
import 'document_viewport.dart';
import 'document_viewer_theme.dart';

/// Where a floating toolbar rests inside the document surface.
enum DocumentToolbarPlacement { bottomCenter, topRight, bottomRight }

/// The outer shell every document type is mounted in.
///
/// Header, floating toolbar, reading area and the opening animation live here,
/// so a PDF, a photograph and a Markdown file are framed identically. Renderers
/// only supply [body] and their own controls.
class DocumentViewerShell extends StatelessWidget {
  const DocumentViewerShell({
    super.key,
    required this.identity,
    required this.body,
    this.actions = const [],
    this.headerLeading,
    this.floatingToolbar,
    this.toolbarPlacement = DocumentToolbarPlacement.bottomCenter,
    this.sidebar,
    this.dense = false,
    this.framed = true,
    this.revealKey,
    this.showHeader = true,
  });

  final DocumentIdentity identity;
  final Widget body;

  /// Controls aligned to the right of the header.
  final List<Widget> actions;
  final Widget? headerLeading;

  /// An optional floating control cluster over the reading area.
  final Widget? floatingToolbar;
  final DocumentToolbarPlacement toolbarPlacement;

  /// Optional leading panel — PDF thumbnails, outlines, archive trees.
  final Widget? sidebar;

  final bool dense;

  /// Draws the outer rounded shell. Disabled when a host already frames it.
  final bool framed;

  /// Changing this cross-fades to a new document.
  final Object? revealKey;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);

    Widget reading = Stack(
      children: [
        Positioned.fill(child: body),
        if (floatingToolbar != null)
          Positioned(
            left: toolbarPlacement == DocumentToolbarPlacement.bottomCenter
                ? 0
                : null,
            right: toolbarPlacement == DocumentToolbarPlacement.bottomCenter
                ? 0
                : 14,
            top: toolbarPlacement == DocumentToolbarPlacement.topRight
                ? 14
                : null,
            bottom: toolbarPlacement == DocumentToolbarPlacement.topRight
                ? null
                : 16,
            child: Align(
              alignment:
                  toolbarPlacement == DocumentToolbarPlacement.bottomCenter
                      ? Alignment.bottomCenter
                      : Alignment.topRight,
              child: floatingToolbar,
            ),
          ),
      ],
    );

    if (sidebar != null) {
      reading = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sidebar!,
          Container(width: 0.6, color: theme.hairline),
          Expanded(child: reading),
        ],
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          DocumentHeader(
            identity: identity,
            actions: actions,
            leading: headerLeading,
            dense: dense,
          ),
        Expanded(child: reading),
      ],
    );

    if (!framed) {
      return DocumentReveal(revealKey: revealKey, child: content);
    }

    final radius = BorderRadius.circular(DocumentViewerTheme.pageRadius);
    return DocumentReveal(
      revealKey: revealKey,
      child: AnimatedContainer(
        duration: AppFlowyMotion.deliberate,
        curve: AppFlowyMotion.standardCurve,
        decoration: BoxDecoration(
          color: theme.canvas,
          borderRadius: radius,
          border: Border.all(color: theme.pageBorder, width: 0.6),
          boxShadow: theme.shellShadow,
        ),
        child: ClipRRect(borderRadius: radius, child: content),
      ),
    );
  }
}

/// A calm, centered message used for empty, oversized and failed documents.
class DocumentNotice extends StatelessWidget {
  const DocumentNotice({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return ColoredBox(
      color: theme.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.control,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.hairline, width: 0.6),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: theme.iconMuted),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: theme.textPrimary,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: theme.textMuted,
                    ),
                  ),
                ],
                if (onAction != null && actionLabel != null) ...[
                  const SizedBox(height: 18),
                  _NoticeAction(label: actionLabel!, onPressed: onAction!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeAction extends StatefulWidget {
  const _NoticeAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_NoticeAction> createState() => _NoticeActionState();
}

class _NoticeActionState extends State<_NoticeAction> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: AppFlowyMotion.fast,
          curve: AppFlowyMotion.standardCurve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          transform: Matrix4.translationValues(0, hovering ? -1 : 0, 0),
          decoration: BoxDecoration(
            color: hovering ? theme.controlHover : theme.control,
            borderRadius:
                BorderRadius.circular(DocumentViewerTheme.controlRadius),
            border: Border.all(color: theme.hairline, width: 0.6),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: theme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
