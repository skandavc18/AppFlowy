import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:flutter/widgets.dart';

/// One contextual strip below page identity, instead of separate decoration,
/// view and creation toolbars. It wraps only when the pane/text scale requires
/// it; no action is silently clipped or hidden in a horizontal scroller.
///
/// The surrounding page supplies [PreviewToolbarRegion]. Geometry, keyboard
/// traversal and child identity survive hover, focus and popup transitions.
class WorkspaceActionRow extends StatelessWidget {
  const WorkspaceActionRow({
    super.key,
    required this.children,
    this.leading,
    this.keepVisible = false,
    this.padding = EdgeInsets.zero,
  });

  /// Persistent navigation beside the contextual actions, outside their fade.
  /// It should shrink-wrap and handle its own wrapping at narrow widths.
  /// Omitting it preserves the single flat reveal row used by other pages.
  final Widget? leading;
  final List<Widget> children;
  final bool keepVisible;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final actions = Wrap(
      spacing: WorkspaceTokens.space2,
      runSpacing: WorkspaceTokens.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
    final content = Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: WorkspaceTokens.controlHeight,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          heightFactor: 1,
          child: leading == null
              ? actions
              : Wrap(
                  spacing: WorkspaceTokens.space2,
                  runSpacing: WorkspaceTokens.space2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    leading!,
                    PreviewToolbar(
                      keepVisible: keepVisible,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 1,
                        heightFactor: 1,
                        child: actions,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
    return leading == null
        ? PreviewToolbar(keepVisible: keepVisible, child: content)
        : content;
  }
}
