import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

@visibleForTesting
const kOfficePanelSurfaceKey = ValueKey('office_panel_surface');

/// The card office status and setup panels sit on, matching embedded
/// previews in every theme including Paper.
class OfficePanelCard extends StatelessWidget {
  const OfficePanelCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: kOfficePanelSurfaceKey,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: officePanelColor(context),
        borderRadius: EditorSurfaceStyle.embedBorderRadius,
        border: Border.all(
          color: EditorSurfaceStyle.embedBorder(context),
        ),
      ),
      child: child,
    );
  }
}

Color officePanelColor(BuildContext context) {
  final theme = AppFlowyTheme.of(context);
  return EditorSurfaceStyle.previewBackgroundFor(
    Theme.of(context).brightness,
    theme.fillColorScheme.content,
    isPaper: PaperTheme.isEnabled(context),
  );
}
