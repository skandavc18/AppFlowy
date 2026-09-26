import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';

/// Navigation changes shape, but the content stays at the same element depth.
/// Resizing a settings window must not discard a draft or its keyboard focus.
class SettingsWorkspaceLayout extends StatelessWidget {
  const SettingsWorkspaceLayout({
    super.key,
    required this.navigation,
    required this.navigationPicker,
    required this.child,
    required this.onClose,
  });

  static const navigationWidth = 232.0;
  static const compactBreakpoint = 840.0;

  final Widget navigation;
  final Widget navigationPicker;
  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final compact = constraints.maxWidth <
            compactBreakpoint + (textScale - 1).clamp(0.0, 1.0) * 160;
        final close = IconButton(
          key: const ValueKey('settings-close'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onClose,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(WorkspaceTokens.controlRadius),
            ),
          ).copyWith(
            animationDuration:
                WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
          ),
          icon: const WorkspaceGlyph(
            Icons.close_rounded,
          ),
        );

        return ColoredBox(
          color: palette.elevatedSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              compact
                  ? Padding(
                      key: const ValueKey('settings-compact-header'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(child: navigationPicker),
                          const SizedBox(width: WorkspaceTokens.space2),
                          close,
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
              Expanded(
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          key: const ValueKey('settings-navigation-rail'),
                          width: compact ? 0 : navigationWidth,
                          child: compact ? null : navigation,
                        ),
                        Expanded(
                          child: FocusTraversalGroup(
                            child: child,
                          ),
                        ),
                      ],
                    ),
                    if (!compact)
                      PositionedDirectional(top: 8, end: 8, child: close),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
