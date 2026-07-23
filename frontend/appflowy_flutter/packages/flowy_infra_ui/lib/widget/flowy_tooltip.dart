import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';

const _tooltipWaitDuration = Duration(milliseconds: 450);

class FlowyTooltip extends StatelessWidget {
  const FlowyTooltip({
    super.key,
    this.message,
    this.richMessage,
    this.preferBelow,
    this.margin,
    this.verticalOffset,
    this.padding,
    this.child,
  });

  final String? message;
  final InlineSpan? richMessage;
  final bool? preferBelow;
  final EdgeInsetsGeometry? margin;
  final Widget? child;
  final double? verticalOffset;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    if (message == null && richMessage == null) {
      return child ?? const SizedBox.shrink();
    }

    return Tooltip(
      margin: margin,
      verticalOffset: verticalOffset ?? 12.0,
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: 8.0,
            vertical: 6.0,
          ),
      decoration: context.tooltipDecoration(),
      waitDuration: _tooltipWaitDuration,
      message: message,
      textStyle: message != null ? context.tooltipTextStyle() : null,
      richMessage: richMessage,
      preferBelow: preferBelow,
      child: child,
    );
  }
}

class ManualTooltip extends StatefulWidget {
  const ManualTooltip({
    super.key,
    this.message,
    this.richMessage,
    this.preferBelow,
    this.margin,
    this.verticalOffset,
    this.padding,
    this.showAutomaticlly = false,
    this.child,
  });

  final String? message;
  final InlineSpan? richMessage;
  final bool? preferBelow;
  final EdgeInsetsGeometry? margin;
  final Widget? child;
  final double? verticalOffset;
  final EdgeInsets? padding;
  final bool showAutomaticlly;

  @override
  State<ManualTooltip> createState() => _ManualTooltipState();
}

class _ManualTooltipState extends State<ManualTooltip> {
  final key = GlobalKey<TooltipState>();

  @override
  void initState() {
    if (widget.showAutomaticlly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) key.currentState?.ensureTooltipVisible();
      });
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: key,
      margin: widget.margin,
      verticalOffset: widget.verticalOffset ?? 12.0,
      triggerMode: widget.showAutomaticlly ? TooltipTriggerMode.manual : null,
      padding: widget.padding ??
          const EdgeInsets.symmetric(
            horizontal: 8.0,
            vertical: 6.0,
          ),
      decoration: context.tooltipDecoration(),
      waitDuration: _tooltipWaitDuration,
      message: widget.message,
      textStyle: widget.message != null ? context.tooltipTextStyle() : null,
      richMessage: widget.richMessage,
      preferBelow: widget.preferBelow,
      child: widget.child,
    );
  }
}

extension FlowyToolTipExtension on BuildContext {
  double tooltipFontSize() => 12.0;

  double tooltipHeight({double? fontSize}) =>
      16.0 / (fontSize ?? tooltipFontSize());

  Color tooltipFontColor() => Theme.of(this).colorScheme.onInverseSurface;

  TextStyle? tooltipTextStyle({Color? fontColor, double? fontSize}) {
    return Theme.of(this).textTheme.bodyMedium?.copyWith(
          color: fontColor ?? tooltipFontColor(),
          fontSize: fontSize ?? tooltipFontSize(),
          fontWeight: flowyRegularFontWeight,
          fontVariations: flowyRegularFontVariations,
          height: tooltipHeight(fontSize: fontSize),
          leadingDistribution: TextLeadingDistribution.even,
        );
  }

  TextStyle? tooltipHintTextStyle({double? fontSize}) => tooltipTextStyle(
        fontColor: tooltipFontColor().withValues(alpha: 0.7),
        fontSize: fontSize,
      );

  Color tooltipBackgroundColor() => Theme.of(this).colorScheme.inverseSurface;

  BoxDecoration tooltipDecoration() {
    final theme = Theme.of(this);
    return BoxDecoration(
      color: tooltipBackgroundColor(),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: tooltipFontColor().withValues(alpha: 0.08),
        width: 0.5,
      ),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: -3,
        ),
      ],
    );
  }
}
