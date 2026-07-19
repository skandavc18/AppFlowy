import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

// This button style is used in
// - Trash button
// - Template button
class SidebarFooterButton extends StatelessWidget {
  const SidebarFooterButton({
    super.key,
    required this.leftIcon,
    required this.text,
    required this.onTap,
  });

  final Widget leftIcon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: HomeSizes.workspaceSectionHeight,
      child: FlowyButton(
        leftIcon: leftIcon,
        leftIconSize: const Size.square(HomeSizes.sidebarActionIconSize),
        iconPadding: HomeSizes.sidebarActionIconTextSpacing,
        margin: const EdgeInsets.symmetric(
          horizontal: HomeSizes.sidebarButtonHorizontalMargin,
        ),
        text: SidebarText(
          text,
        ),
        onTap: onTap,
      ),
    );
  }
}
