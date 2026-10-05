import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_preview.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_templates.dart';
import 'package:appflowy/plugins/templates/presentation/template_card.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One starting point the gallery offers.
class _Entry {
  const _Entry({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.accent,
    required this.document,
    required this.onTap,
  });

  factory _Entry.arrangement(DashboardTemplate template, VoidCallback onTap) =>
      _Entry(
        id: template.id,
        label: template.label,
        description: template.description,
        icon: template.icon,
        accent: template.accent,
        document: template.build,
        onTap: onTap,
      );

  factory _Entry.board(WorkspaceTemplate template, VoidCallback onTap) =>
      _Entry(
        id: template.id,
        label: template.label,
        description: template.description,
        icon: template.icon,
        accent: template.accent,
        document: () => (template.boardPart!.blueprint as TemplateDashboard)
            .build(const {}),
        onTap: onTap,
      );

  final String id;
  final String Function() label;
  final String Function() description;
  final IconData icon;
  final DashboardAccent accent;
  final DashboardDocument Function() document;
  final VoidCallback onTap;
}

/// What an empty dashboard offers: a blank canvas, or a starting point.
class DashboardTemplateGallery extends StatelessWidget {
  const DashboardTemplateGallery({
    super.key,
    required this.palette,
    required this.onChosen,
    this.onBoardChosen,
    this.embedded = false,
  });

  final DashboardPalette palette;
  final ValueChanged<DashboardTemplate> onChosen;

  /// A board that brings its own tables. Offered only when somebody can
  /// make those tables.
  final ValueChanged<WorkspaceTemplate>? onBoardChosen;
  final bool embedded;

  List<_Entry> _entries() {
    final arrangements = dashboardTemplates();
    final onBoard = onBoardChosen;
    return [
      for (final template in arrangements.take(1))
        _Entry.arrangement(template, () => onChosen(template)),
      if (onBoard != null)
        for (final template in TemplateRegistry.boards())
          if (missingExtensionsFor(template).isEmpty)
            _Entry.board(template, () => onBoard(template)),
      for (final template in arrangements.skip(1))
        _Entry.arrangement(template, () => onChosen(template)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: SingleChildScrollView(
          primary: !embedded,
          physics: embedded ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(
                    alpha: palette.isDark ? 0.2 : 0.12,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.dashboard_customize_rounded,
                  size: 24,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                LocaleKeys.dashboard_empty_title.tr(),
                textAlign: TextAlign.center,
                style: DashboardType.display(palette, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                LocaleKeys.dashboard_empty_body.tr(),
                textAlign: TextAlign.center,
                style: DashboardType.caption(palette).copyWith(fontSize: 13.5),
              ),
              const SizedBox(height: 28),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 204,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: entries.length,
                itemBuilder: (_, index) {
                  final entry = entries[index];
                  return _TemplateCard(
                    key: ValueKey('dashboard-template-${entry.id}'),
                    entry: entry,
                    palette: palette,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({
    super.key,
    required this.entry,
    required this.palette,
  });

  final _Entry entry;
  final DashboardPalette palette;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _hovered = false;

  // A template mints fresh ids each time it is built; one picture is enough.
  late final DashboardDocument _document = widget.entry.document();

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final template = widget.entry;
    final neutral = template.accent == DashboardAccent.neutral;
    final tone = palette.toneFor(template.accent);
    final strong = neutral ? palette.accent : tone.strong;
    // The template's own colour, laid behind a small picture of its board.
    final backdrop = neutral || tone.gradient.length < 2
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              for (final colour in tone.gradient)
                colour.withValues(alpha: palette.isDark ? 0.42 : 0.78),
            ],
          );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.entry.onTap,
        child: AnimatedSlide(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          offset: Offset(0, _hovered ? -0.01 : 0),
          child: AnimatedContainer(
            duration: DashboardMetrics.hover,
            curve: DashboardMetrics.curve,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
              boxShadow: palette.cardShadow(raised: _hovered),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: backdrop == null ? palette.sunken : null,
                      gradient: backdrop,
                      borderRadius:
                          BorderRadius.circular(DashboardMetrics.innerRadius),
                    ),
                    child: _document.widgetCount == 0
                        ? Center(
                            child: AnimatedScale(
                              duration: DashboardMetrics.hover,
                              curve: DashboardMetrics.curve,
                              scale: _hovered ? 1.08 : 1,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: palette.surface,
                                  shape: BoxShape.circle,
                                  boxShadow: palette.cardShadow(),
                                ),
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 22,
                                  color: strong,
                                ),
                              ),
                            ),
                          )
                        : AnimatedScale(
                            duration: DashboardMetrics.hover,
                            curve: DashboardMetrics.curve,
                            scale: _hovered ? 1.03 : 1,
                            alignment: Alignment.topCenter,
                            child: IgnorePointer(
                              child: DashboardMiniature(document: _document),
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(template.icon, size: 16, color: strong),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              template.label(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DashboardType.cardTitle(
                                palette,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              template.description(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: DashboardType.caption(palette),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
