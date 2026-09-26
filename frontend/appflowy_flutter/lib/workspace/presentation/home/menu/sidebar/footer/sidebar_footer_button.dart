import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:flutter/material.dart';

// This button style is used in
// - Trash button
class SidebarFooterButton extends StatelessWidget {
  const SidebarFooterButton({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
    this.compact = false,
  });

  final SidebarIcon icon;
  final String text;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SidebarIconButton(
        icon: icon,
        tooltip: text,
        dimension: WorkspaceTokens.controlHeight,
        onPressed: onTap,
      );
    }
    return SidebarNavItem(
      icon: icon,
      label: text,
      onTap: onTap,
    );
  }
}
