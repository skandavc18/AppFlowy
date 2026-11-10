import 'package:appflowy/shared/workspace_design.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// Lets a host that already shows the page title, such as the mobile settings
/// app bar, keep a page's description without repeating its title.
class SettingsHeaderScope extends InheritedWidget {
  const SettingsHeaderScope({
    super.key,
    required this.showTitle,
    required super.child,
  });

  final bool showTitle;

  static bool showsTitle(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsHeaderScope>()
          ?.showTitle ??
      true;

  @override
  bool updateShouldNotify(SettingsHeaderScope oldWidget) =>
      oldWidget.showTitle != showTitle;
}

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
    final showTitle = SettingsHeaderScope.showsTitle(context);
    final descriptionSpacing = showTitle
        ? const VSpace(WorkspaceTokens.space3)
        : const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle)
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
          descriptionSpacing,
          DefaultTextStyle(
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.body,
              color: WorkspacePalette.of(context).secondaryText,
            ),
            child: descriptionBuilder!(context),
          ),
        ] else if (description?.isNotEmpty == true) ...[
          descriptionSpacing,
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
