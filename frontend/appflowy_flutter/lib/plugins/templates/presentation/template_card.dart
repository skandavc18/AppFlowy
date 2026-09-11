import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/built_in_templates.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Which of a template's extensions are not switched on right now.
List<String> missingExtensionsFor(WorkspaceTemplate template) => [
      for (final id in template.requires)
        if (!DartExtensionHost.instance.isActive(id)) id,
    ];

/// One template, offered.
///
/// A template whose extension is off is still shown — hiding it would leave
/// somebody hunting for a card they remember. It says what it needs and
/// offers to turn it on instead.
class TemplateCard extends StatefulWidget {
  const TemplateCard({
    super.key,
    required this.template,
    required this.palette,
    required this.onChosen,
    this.compact = false,
  });

  final WorkspaceTemplate template;
  final DashboardPalette palette;
  final VoidCallback onChosen;
  final bool compact;

  @override
  State<TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<TemplateCard> {
  bool _hovered = false;
  bool _enabling = false;

  Future<void> _turnOn(List<String> missing) async {
    setState(() => _enabling = true);
    for (final id in missing) {
      await DartExtensionHost.instance.setEnabled(id, true);
    }
    if (mounted) {
      setState(() => _enabling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final palette = widget.palette;
    final tone = palette.toneFor(template.accent);
    final missing = missingExtensionsFor(template);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // Without this the card's own 15px padding hits nothing, so a press
        // near its edge is swallowed and the card reads as a dead button.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onChosen,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: tone.surface,
            borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
            boxShadow: palette.cardShadow(raised: _hovered),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.wash(0.18),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(template.icon, size: 19, color: tone.strong),
                  ),
                  const SizedBox(width: 12),
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
                        const SizedBox(height: 3),
                        Text(
                          template.description(),
                          maxLines: widget.compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardType.caption(palette)
                              .copyWith(fontSize: 12, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (missing.isNotEmpty)
                _NeedsExtension(
                  palette: palette,
                  names: missing,
                  busy: _enabling,
                  onTurnOn: () => _turnOn(missing),
                )
              else
                _Footprint(template: template, palette: palette),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the template will make, so nobody presses it blind.
class _Footprint extends StatelessWidget {
  const _Footprint({required this.template, required this.palette});

  final WorkspaceTemplate template;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) {
    final kind = template.kind;
    final parts = template.parts.length;
    return Row(
      children: [
        Icon(kind.icon, size: 13, color: palette.textMuted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            kind.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardType.caption(palette).copyWith(fontSize: 11.5),
          ),
        ),
        if (parts > 1) ...[
          const SizedBox(width: 6),
          Text(
            '·',
            style: DashboardType.caption(palette).copyWith(fontSize: 11.5),
          ),
          const SizedBox(width: 6),
          Text(
            LocaleKeys.templates_parts.tr(args: ['$parts']),
            style: DashboardType.caption(palette).copyWith(fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class _NeedsExtension extends StatelessWidget {
  const _NeedsExtension({
    required this.palette,
    required this.names,
    required this.busy,
    required this.onTurnOn,
  });

  final DashboardPalette palette;
  final List<String> names;
  final bool busy;
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final tone = palette.toneFor(DashboardAccent.amber);
    final label = names.length == 1
        ? LocaleKeys.templates_needsExtension.tr(args: [names.single])
        : LocaleKeys.templates_needsExtensions.tr(args: [names.join(', ')]);
    return Row(
      children: [
        Icon(Icons.extension_rounded, size: 13, color: tone.strong),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardType.caption(palette)
                .copyWith(fontSize: 11.5, color: tone.strong),
          ),
        ),
        const SizedBox(width: 6),
        if (busy)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: tone.strong,
            ),
          )
        else
          _TinyButton(
            label: LocaleKeys.templates_turnOn.tr(),
            tone: tone,
            onTap: onTurnOn,
          ),
      ],
    );
  }
}

class _TinyButton extends StatelessWidget {
  const _TinyButton({
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final DashboardTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Deeper than the card's own tap, so it wins the arena.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tone.wash(0.18),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tone.strong,
              ),
            ),
          ),
        ),
      );
}
