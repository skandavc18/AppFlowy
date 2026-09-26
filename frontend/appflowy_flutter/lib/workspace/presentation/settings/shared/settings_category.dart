import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// Renders a simple category taking a title and the list
/// of children (settings) to be rendered.
///
class SettingsCategory extends StatelessWidget {
  const SettingsCategory({
    super.key,
    required this.title,
    this.description,
    this.descriptionColor,
    this.tooltip,
    this.actions,
    required this.children,
  });

  final String title;
  final String? description;
  final Color? descriptionColor;
  final String? tooltip;
  final List<Widget>? actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.section,
                  ),
                ),
              ),
            ),
            if (tooltip != null) ...[
              const HSpace(WorkspaceTokens.space2),
              FlowyTooltip(
                message: tooltip,
                child: const WorkspaceGlyph.svg(
                  FlowySvgs.information_s,
                  size: 16,
                ),
              ),
            ],
          ],
        ),
        if (description?.isNotEmpty ?? false) ...[
          const VSpace(WorkspaceTokens.space2),
          Text(
            description!,
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.body,
              color: descriptionColor ??
                  WorkspacePalette.of(context).secondaryText,
            ),
          ),
        ],
        if (actions?.isNotEmpty ?? false) ...[
          const VSpace(WorkspaceTokens.space3),
          Wrap(
            spacing: WorkspaceTokens.space2,
            runSpacing: WorkspaceTokens.space2,
            children: actions!,
          ),
        ],
        const VSpace(WorkspaceTokens.space4),
        SeparatedColumn(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          separatorBuilder: () =>
              children.length > 1 ? const VSpace(16) : const SizedBox.shrink(),
          children: children,
        ),
      ],
    );
  }
}
