import 'package:appflowy_ui/src/theme/theme.dart';
import 'package:flutter/material.dart';

typedef AFBaseButtonColorBuilder = Color Function(
  BuildContext context,
  bool isHovering,
  bool disabled,
);

typedef AFBaseButtonBorderColorBuilder = Color Function(
  BuildContext context,
  bool isHovering,
  bool disabled,
  bool isFocused,
);

class AFBaseButton extends StatefulWidget {
  const AFBaseButton({
    super.key,
    required this.onTap,
    required this.builder,
    required this.padding,
    required this.borderRadius,
    this.borderColor,
    this.backgroundColor,
    this.ringColor,
    this.disabled = false,
    this.autofocus = false,
    this.showFocusRing = true,
  });

  final VoidCallback? onTap;

  final AFBaseButtonBorderColorBuilder? borderColor;
  final AFBaseButtonBorderColorBuilder? ringColor;
  final AFBaseButtonColorBuilder? backgroundColor;

  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool disabled;
  final bool autofocus;
  final bool showFocusRing;

  final Widget Function(
    BuildContext context,
    bool isHovering,
    bool disabled,
  ) builder;

  @override
  State<AFBaseButton> createState() => _AFBaseButtonState();
}

class _AFBaseButtonState extends State<AFBaseButton> {
  final FocusNode focusNode = FocusNode();

  bool isHovering = false;
  bool isFocused = false;
  bool isPressed = false;

  bool get isDisabled => widget.disabled || widget.onTap == null;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color borderColor = _buildBorderColor(context);
    final Color backgroundColor = _buildBackgroundColor(context);
    final Color ringColor = _buildRingColor(context);

    return Semantics(
      button: true,
      enabled: !isDisabled,
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (!isDisabled) {
                widget.onTap?.call();
              }
              return;
            },
          ),
        },
        child: Focus(
          focusNode: focusNode,
          onFocusChange: (isFocused) {
            setState(() => this.isFocused = isFocused);
          },
          autofocus: widget.autofocus,
          child: MouseRegion(
            cursor: isDisabled
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            onEnter: (_) {
              if (!isDisabled) setState(() => isHovering = true);
            },
            onExit: (_) => setState(() {
              isHovering = false;
              isPressed = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isDisabled ? null : widget.onTap,
              onTapDown:
                  isDisabled ? null : (_) => setState(() => isPressed = true),
              onTapUp:
                  isDisabled ? null : (_) => setState(() => isPressed = false),
              onTapCancel:
                  isDisabled ? null : () => setState(() => isPressed = false),
              child: AnimatedContainer(
                duration: AppFlowyMotion.fast,
                curve: AppFlowyMotion.standardCurve,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: isFocused && widget.showFocusRing
                        ? ringColor
                        : Colors.transparent,
                    width: 1.5,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                ),
                child: AnimatedContainer(
                  duration: AppFlowyMotion.fast,
                  curve: AppFlowyMotion.standardCurve,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    border: Border.all(color: borderColor, width: 0.6),
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                  ),
                  child: Padding(
                    padding: widget.padding,
                    child: widget.builder(
                      context,
                      isHovering,
                      isDisabled,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _buildBorderColor(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return widget.borderColor
            ?.call(context, isHovering, isDisabled, isFocused) ??
        theme.borderColorScheme.primary;
  }

  Color _buildBackgroundColor(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final background =
        widget.backgroundColor?.call(context, isHovering, isDisabled) ??
            theme.fillColorScheme.content;
    if (isPressed && !isDisabled) {
      return Color.alphaBlend(
        theme.fillColorScheme.contentVisible,
        background,
      );
    }
    return background;
  }

  Color _buildRingColor(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    if (widget.ringColor != null) {
      return widget.ringColor!.call(context, isHovering, isDisabled, isFocused);
    }

    if (isFocused) {
      return theme.borderColorScheme.themeThick.withAlpha(128);
    }

    return Colors.transparent;
  }
}
