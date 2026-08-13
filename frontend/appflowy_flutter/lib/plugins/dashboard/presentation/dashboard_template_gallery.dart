import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_templates.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What an empty dashboard offers: a blank canvas, or a starting point.
class DashboardTemplateGallery extends StatelessWidget {
  const DashboardTemplateGallery({
    super.key,
    required this.palette,
    required this.onChosen,
  });

  final DashboardPalette palette;
  final ValueChanged<DashboardTemplate> onChosen;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.dashboard_customize_rounded,
                  size: 30,
                  color: palette.accent,
                ),
                const SizedBox(height: 14),
                Text(
                  LocaleKeys.dashboard_empty_title.tr(),
                  style: DashboardType.title(palette),
                ),
                const SizedBox(height: 6),
                Text(
                  LocaleKeys.dashboard_empty_body.tr(),
                  textAlign: TextAlign.center,
                  style: DashboardType.caption(palette).copyWith(fontSize: 13),
                ),
                const SizedBox(height: 26),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisExtent: 96,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: dashboardTemplates().length,
                  itemBuilder: (_, index) {
                    final template = dashboardTemplates()[index];
                    return _TemplateCard(
                      template: template,
                      palette: palette,
                      onTap: () => onChosen(template),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
}

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({
    required this.template,
    required this.palette,
    required this.onTap,
  });

  final DashboardTemplate template;
  final DashboardPalette palette;
  final VoidCallback onTap;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final tone = palette.toneFor(widget.template.accent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tone.surface,
            borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
            boxShadow: palette.cardShadow(raised: _hovered),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.wash(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.template.icon,
                  size: 18,
                  color: tone.strong,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.template.label(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.cardTitle(
                        palette,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Text(
                        widget.template.description(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.caption(palette),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
