import 'package:appflowy_ui/src/theme/appflowy_theme.dart';
import 'package:flutter/widgets.dart';

enum AFButtonSize {
  s,
  m,
  l,
  xl;

  TextStyle buildTextStyle(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return switch (this) {
      AFButtonSize.s => theme.textStyle.body.enhanced(),
      AFButtonSize.m => theme.textStyle.body.enhanced(),
      AFButtonSize.l => theme.textStyle.body.enhanced(),
      AFButtonSize.xl => theme.textStyle.title.enhanced(),
    };
  }

  EdgeInsetsGeometry buildPadding(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return switch (this) {
      AFButtonSize.s => EdgeInsets.symmetric(
          horizontal: 10,
          vertical: theme.spacing.xs,
        ),
      AFButtonSize.m => EdgeInsets.symmetric(
          horizontal: theme.spacing.l,
          vertical: theme.spacing.s,
        ),
      AFButtonSize.l => EdgeInsets.symmetric(
          horizontal: 14,
          vertical: theme.spacing.m,
        ),
      AFButtonSize.xl => EdgeInsets.symmetric(
          horizontal: theme.spacing.xl,
          vertical: 10,
        ),
    };
  }

  double buildBorderRadius(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return switch (this) {
      AFButtonSize.s => theme.borderRadius.m,
      AFButtonSize.m => theme.borderRadius.m,
      AFButtonSize.l => 10,
      AFButtonSize.xl => 10,
    };
  }
}
