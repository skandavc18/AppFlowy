import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

export 'dimension.dart';

class AFModal extends StatelessWidget {
  const AFModal({
    super.key,
    this.constraints = const BoxConstraints(),
    this.backgroundColor,
    required this.child,
  });

  final BoxConstraints constraints;
  final Color? backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    const radius = BorderRadius.all(Radius.circular(24));

    return Center(
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.xl),
        child: ConstrainedBox(
          constraints: constraints,
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: theme.shadow.medium,
              borderRadius: radius,
              color: backgroundColor ?? Theme.of(context).dialogBackgroundColor,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AFModalHeader extends StatelessWidget {
  const AFModalHeader({
    super.key,
    required this.leading,
    this.trailing = const [],
  });

  final Widget leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        top: theme.spacing.xl,
        left: theme.spacing.xxl,
        right: theme.spacing.xxl,
      ),
      child: DefaultTextStyle(
        style: theme.textStyle.heading4
            .prominent(
              color: theme.textColorScheme.primary,
            )
            .copyWith(fontSize: 20, height: 1.3),
        child: Row(
          spacing: theme.spacing.s,
          children: [
            Expanded(child: leading),
            ...trailing,
          ],
        ),
      ),
    );
  }
}

class AFModalFooter extends StatelessWidget {
  const AFModalFooter({
    super.key,
    this.leading = const [],
    this.trailing = const [],
  });

  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: theme.spacing.xl,
        left: theme.spacing.xxl,
        right: theme.spacing.xxl,
      ),
      child: OverflowBar(
        alignment: leading.isEmpty
            ? MainAxisAlignment.end
            : MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: theme.spacing.l,
        overflowSpacing: theme.spacing.m,
        children: [
          if (leading.isNotEmpty)
            Wrap(
              spacing: theme.spacing.m,
              runSpacing: theme.spacing.m,
              children: leading,
            ),
          if (trailing.isNotEmpty)
            Wrap(
              spacing: theme.spacing.m,
              runSpacing: theme.spacing.m,
              children: trailing,
            ),
        ],
      ),
    );
  }
}

class AFModalBody extends StatelessWidget {
  const AFModalBody({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: theme.spacing.l,
        horizontal: theme.spacing.xxl,
      ),
      child: child,
    );
  }
}
