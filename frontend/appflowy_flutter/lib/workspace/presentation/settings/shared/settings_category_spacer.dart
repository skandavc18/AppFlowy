import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:flutter/material.dart';

/// Settings sections are separated by breathing room, not nested rules.
///
class SettingsCategorySpacer extends StatelessWidget {
  const SettingsCategorySpacer({
    super.key,
    this.topSpacing,
    this.bottomSpacing,
  });

  final double? topSpacing;
  final double? bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: (topSpacing ?? WorkspaceTokens.space6) +
          (bottomSpacing ?? WorkspaceTokens.space6),
    );
  }
}
