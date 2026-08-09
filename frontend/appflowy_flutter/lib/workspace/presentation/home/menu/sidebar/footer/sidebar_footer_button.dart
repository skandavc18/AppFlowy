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
  });

  final SidebarIcon icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SidebarNavItem(
      icon: icon,
      label: text,
      onTap: onTap,
    );
  }
}
