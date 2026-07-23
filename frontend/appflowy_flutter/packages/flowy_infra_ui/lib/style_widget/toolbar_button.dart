import 'package:flowy_infra/size.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';

class FlowyToolbarButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsets padding;
  final String? tooltip;

  const FlowyToolbarButton({
    super.key,
    this.onPressed,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tooltipMessage = tooltip ?? '';

    return FlowyTooltip(
      message: tooltipMessage,
      child: RawMaterialButton(
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
        hoverElevation: 0,
        highlightElevation: 0,
        padding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Corners.s8Border),
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        elevation: 0,
        onPressed: onPressed,
        child: FlowyHover(
          style: HoverStyle(
            hoverColor: Theme.of(context).hoverColor,
            borderRadius: Corners.s8Border,
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
