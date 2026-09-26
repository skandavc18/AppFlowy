import 'package:appflowy/shared/workspace_design.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// Renders a simple header for the settings view
///
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({
    super.key,
    required this.title,
    this.description,
    this.descriptionBuilder,
  });

  final String title;
  final String? description;
  final WidgetBuilder? descriptionBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.pageTitle,
            ),
          ),
        ),
        if (descriptionBuilder != null) ...[
          const VSpace(WorkspaceTokens.space3),
          DefaultTextStyle(
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.body,
              color: WorkspacePalette.of(context).secondaryText,
            ),
            child: descriptionBuilder!(context),
          ),
        ] else if (description?.isNotEmpty == true) ...[
          const VSpace(WorkspaceTokens.space3),
          Text(
            description!,
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.body,
              color: WorkspacePalette.of(context).secondaryText,
            ),
          ),
        ],
      ],
    );
  }
}
