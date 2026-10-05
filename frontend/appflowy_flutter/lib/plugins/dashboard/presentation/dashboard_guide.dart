import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// How to use a board, in a few numbered steps, until somebody has read it.
class DashboardGuideCard extends StatelessWidget {
  const DashboardGuideCard({
    super.key,
    required this.steps,
    required this.palette,
    this.onDismiss,
  });

  final List<String> steps;
  final DashboardPalette palette;

  /// Removes the guide for good. Without it the card cannot be closed.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final accent = palette.accent;
    final dismiss = onDismiss;
    return Container(
      key: const ValueKey('dashboard-guide'),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: palette.isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
        border: Border.all(
          color: accent.withValues(alpha: palette.isDark ? 0.28 : 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 17, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  LocaleKeys.templates_guide_title.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardType.cardTitle(
                    palette,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (dismiss != null)
                TextButton(
                  key: const ValueKey('dashboard-guide-dismiss'),
                  onPressed: dismiss,
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(LocaleKeys.templates_guide_dismiss.tr()),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final items = [
                for (var index = 0; index < steps.length; index++)
                  _Step(
                    number: index + 1,
                    text: steps[index],
                    palette: palette,
                  ),
              ];
              // Side by side while each step still has room for its words.
              if (constraints.maxWidth >= 620) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      if (index > 0) const SizedBox(width: 18),
                      Expanded(child: items[index]),
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    if (index > 0) const SizedBox(height: 10),
                    items[index],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.text,
    required this.palette,
  });

  final int number;
  final String text;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accent.withValues(
                alpha: palette.isDark ? 0.24 : 0.14,
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: DashboardType.caption(palette).copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: palette.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: DashboardType.caption(palette).copyWith(
                  fontSize: 12.5,
                  height: 1.4,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ),
        ],
      );
}
