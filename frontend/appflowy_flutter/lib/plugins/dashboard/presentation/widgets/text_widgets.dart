import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';

/// Words, and the quiet furniture around them.
///
/// A dashboard is not only readouts: a heading, a note to yourself and a line
/// between two groups of cards are what make one legible.
void registerDashboardTextWidgets() {
  DashboardWidgetRegistry.register(_heading);
  DashboardWidgetRegistry.register(_text);
  DashboardWidgetRegistry.register(_quote);
  DashboardWidgetRegistry.register(_callout);
  DashboardWidgetRegistry.register(_stickyNote);
  DashboardWidgetRegistry.register(_divider);
  DashboardWidgetRegistry.register(_spacer);
}

const _keyText = 'text';
const _keyLevel = 'level';
const _keyAlign = 'align';
const _keyIcon = 'icon';
const _keyAuthor = 'author';
const _keyStyle = 'style';

TextAlign _alignOf(String value) => switch (value) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.start,
    };

List<DashboardConfigField> _alignField(DashboardWidgetContext context) => [
      DashboardConfigChoice(
        label: LocaleKeys.dashboard_config_align.tr(),
        value: context.spec.setting(_keyAlign, fallback: 'left'),
        choices: [
          DashboardChoice(
            value: 'left',
            label: LocaleKeys.dashboard_align_left.tr(),
            icon: Icons.format_align_left_rounded,
          ),
          DashboardChoice(
            value: 'center',
            label: LocaleKeys.dashboard_align_center.tr(),
            icon: Icons.format_align_center_rounded,
          ),
          DashboardChoice(
            value: 'right',
            label: LocaleKeys.dashboard_align_right.tr(),
            icon: Icons.format_align_right_rounded,
          ),
        ],
        iconsOnly: true,
        onChanged: (value) => context.setSettings({_keyAlign: value}),
      ),
    ];

final _heading = DashboardWidgetDefinition(
  type: 'heading',
  label: () => LocaleKeys.dashboard_widget_heading.tr(),
  description: () => LocaleKeys.dashboard_widget_headingHint.tr(),
  icon: Icons.title_rounded,
  group: DashboardWidgetGroup.text,
  defaultColumnSpan: 12,
  defaultRowSpan: 1,
  showsTitleByDefault: false,
  paintsOwnSurface: true,
  padding: const EdgeInsets.symmetric(horizontal: 2),
  slashName: 'heading',
  keywords: const ['heading', 'title', 'header', 'h1', 'h2'],
  builder: (context) {
    final level = context.spec.integer(_keyLevel, fallback: 2).clamp(1, 3);
    final size = switch (level) { 1 => 26.0, 2 => 20.0, _ => 16.0 };
    return Align(
      alignment: switch (context.spec.setting(_keyAlign, fallback: 'left')) {
        'center' => Alignment.center,
        'right' => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      child: DashboardEditableText(
        value: context.spec.setting(_keyText),
        hint: LocaleKeys.dashboard_widget_headingHint.tr(),
        palette: context.palette,
        enabled: context.isTypable,
        textAlign: _alignOf(context.spec.setting(_keyAlign, fallback: 'left')),
        style: DashboardType.title(context.palette, size: size)
            .copyWith(color: context.tone.ink),
        onChanged: (value) => context.setSettings({_keyText: value}),
      ),
    );
  },
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_text.tr(),
      value: context.spec.setting(_keyText),
      onChanged: (value) => context.setSettings({_keyText: value}),
    ),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_level.tr(),
      value: '${context.spec.integer(_keyLevel, fallback: 2)}',
      choices: const [
        DashboardChoice(value: '1', label: 'H1'),
        DashboardChoice(value: '2', label: 'H2'),
        DashboardChoice(value: '3', label: 'H3'),
      ],
      onChanged: (value) =>
          context.setSettings({_keyLevel: int.tryParse(value) ?? 2}),
    ),
    ..._alignField(context),
  ],
);

final _text = DashboardWidgetDefinition(
  type: 'text',
  label: () => LocaleKeys.dashboard_widget_text.tr(),
  description: () => LocaleKeys.dashboard_widget_textHint.tr(),
  icon: Icons.notes_rounded,
  group: DashboardWidgetGroup.text,
  defaultRowSpan: 3,
  showsTitleByDefault: false,
  slashName: 'note',
  keywords: const ['text', 'note', 'paragraph', 'body', 'notes'],
  builder: (context) => Align(
    alignment: Alignment.topLeft,
    child: DashboardEditableText(
      value: context.spec.setting(_keyText),
      hint: LocaleKeys.dashboard_widget_textHint.tr(),
      palette: context.palette,
      enabled: context.isTypable,
      multiline: true,
      textAlign: _alignOf(context.spec.setting(_keyAlign, fallback: 'left')),
      style: DashboardType.body(context.palette, color: context.tone.ink),
      onChanged: (value) => context.setSettings({_keyText: value}),
    ),
  ),
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_text.tr(),
      value: context.spec.setting(_keyText),
      multiline: true,
      onChanged: (value) => context.setSettings({_keyText: value}),
    ),
    ..._alignField(context),
  ],
);

final _quote = DashboardWidgetDefinition(
  type: 'quote',
  label: () => LocaleKeys.dashboard_widget_quote.tr(),
  icon: Icons.format_quote_rounded,
  group: DashboardWidgetGroup.text,
  defaultRowSpan: 3,
  showsTitleByDefault: false,
  keywords: const ['quote', 'citation', 'saying'],
  builder: (context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 3,
          decoration: BoxDecoration(
            color: context.strong.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: DashboardEditableText(
                  value: context.spec.setting(_keyText),
                  hint: LocaleKeys.dashboard_widget_quoteHint.tr(),
                  palette: palette,
                  enabled: context.isTypable,
                  multiline: true,
                  style: DashboardType.body(palette).copyWith(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                  ),
                  onChanged: (value) => context.setSettings({_keyText: value}),
                ),
              ),
              const SizedBox(height: 6),
              DashboardEditableText(
                value: context.spec.setting(_keyAuthor),
                hint: LocaleKeys.dashboard_widget_quoteAuthor.tr(),
                palette: palette,
                enabled: context.isTypable,
                style: DashboardType.caption(palette),
                onChanged: (value) => context.setSettings({_keyAuthor: value}),
              ),
            ],
          ),
        ),
      ],
    );
  },
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_text.tr(),
      value: context.spec.setting(_keyText),
      multiline: true,
      onChanged: (value) => context.setSettings({_keyText: value}),
    ),
    DashboardConfigText(
      label: LocaleKeys.dashboard_widget_quoteAuthor.tr(),
      value: context.spec.setting(_keyAuthor),
      onChanged: (value) => context.setSettings({_keyAuthor: value}),
    ),
  ],
);

final _callout = DashboardWidgetDefinition(
  type: 'callout',
  label: () => LocaleKeys.dashboard_widget_callout.tr(),
  icon: Icons.campaign_rounded,
  group: DashboardWidgetGroup.text,
  defaultColumnSpan: 6,
  defaultRowSpan: 2,
  defaultAccent: DashboardAccent.blue,
  showsTitleByDefault: false,
  defaultSettings: const {_keyIcon: '💡'},
  keywords: const ['callout', 'notice', 'tip', 'warning', 'info'],
  builder: (context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.spec.setting(_keyIcon, fallback: '💡'),
        style: const TextStyle(fontSize: 18),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: DashboardEditableText(
          value: context.spec.setting(_keyText),
          hint: LocaleKeys.dashboard_widget_calloutHint.tr(),
          palette: context.palette,
          enabled: context.isTypable,
          multiline: true,
          style: DashboardType.body(context.palette, color: context.tone.ink),
          onChanged: (value) => context.setSettings({_keyText: value}),
        ),
      ),
    ],
  ),
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_icon.tr(),
      value: context.spec.setting(_keyIcon, fallback: '💡'),
      onChanged: (value) => context.setSettings({_keyIcon: value}),
    ),
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_text.tr(),
      value: context.spec.setting(_keyText),
      multiline: true,
      onChanged: (value) => context.setSettings({_keyText: value}),
    ),
  ],
);

final _stickyNote = DashboardWidgetDefinition(
  type: 'sticky_note',
  label: () => LocaleKeys.dashboard_widget_stickyNote.tr(),
  icon: Icons.sticky_note_2_rounded,
  group: DashboardWidgetGroup.text,
  defaultColumnSpan: 3,
  defaultAccent: DashboardAccent.amber,
  showsTitleByDefault: false,
  keywords: const ['sticky', 'note', 'memo', 'postit', 'reminder note'],
  builder: (context) => Align(
    alignment: Alignment.topLeft,
    child: DashboardEditableText(
      value: context.spec.setting(_keyText),
      hint: LocaleKeys.dashboard_widget_stickyHint.tr(),
      palette: context.palette,
      enabled: context.isTypable,
      multiline: true,
      style:
          DashboardType.body(context.palette, color: context.tone.ink).copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontVariations: flowyFontVariationsForWeight(FontWeight.w500),
      ),
      onChanged: (value) => context.setSettings({_keyText: value}),
    ),
  ),
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_text.tr(),
      value: context.spec.setting(_keyText),
      multiline: true,
      onChanged: (value) => context.setSettings({_keyText: value}),
    ),
  ],
);

final _divider = DashboardWidgetDefinition(
  type: 'divider',
  label: () => LocaleKeys.dashboard_widget_divider.tr(),
  icon: Icons.horizontal_rule_rounded,
  group: DashboardWidgetGroup.text,
  defaultColumnSpan: 12,
  defaultRowSpan: 1,
  showsTitleByDefault: false,
  paintsOwnSurface: true,
  keywords: const ['divider', 'rule', 'line', 'separator'],
  builder: (context) {
    final style = context.spec.setting(_keyStyle, fallback: 'line');
    final colour = context.palette.gridLine;
    return Center(
      child: style == 'dots'
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.palette.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            )
          : Container(height: 1, color: colour),
    );
  },
  configure: (context) => [
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_style.tr(),
      value: context.spec.setting(_keyStyle, fallback: 'line'),
      choices: [
        DashboardChoice(
          value: 'line',
          label: LocaleKeys.dashboard_divider_line.tr(),
        ),
        DashboardChoice(
          value: 'dots',
          label: LocaleKeys.dashboard_divider_dots.tr(),
        ),
      ],
      onChanged: (value) => context.setSettings({_keyStyle: value}),
    ),
  ],
);

final _spacer = DashboardWidgetDefinition(
  type: 'spacer',
  label: () => LocaleKeys.dashboard_widget_spacer.tr(),
  icon: Icons.space_bar_rounded,
  group: DashboardWidgetGroup.text,
  defaultRowSpan: 1,
  showsTitleByDefault: false,
  paintsOwnSurface: true,
  keywords: const ['spacer', 'gap', 'space', 'blank', 'divider', 'rule'],
  builder: (context) => _SpacerBody(context: context),
  configure: (context) => [
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_style.tr(),
      value: context.spec.setting(_keyStyle, fallback: 'blank'),
      choices: [
        DashboardChoice(
          value: 'blank',
          label: LocaleKeys.dashboard_spacer_blank.tr(),
        ),
        DashboardChoice(
          value: 'line',
          label: LocaleKeys.dashboard_spacer_line.tr(),
        ),
        DashboardChoice(
          value: 'dots',
          label: LocaleKeys.dashboard_spacer_dots.tr(),
        ),
      ],
      onChanged: (value) => context.setSettings({_keyStyle: value}),
    ),
    DashboardConfigAccent(
      label: LocaleKeys.dashboard_config_colour.tr(),
      value: context.spec.accent,
      onChanged: (accent) =>
          context.update((spec) => spec.copyWith(accent: accent)),
    ),
  ],
);

/// Empty room, a rule, or a row of dots — in the widget's own colour.
class _SpacerBody extends StatelessWidget {
  const _SpacerBody({required this.context});

  final DashboardWidgetContext context;

  @override
  Widget build(BuildContext build) {
    final style = context.spec.setting(_keyStyle, fallback: 'blank');
    final ink = context.spec.accent == DashboardAccent.neutral
        ? context.palette.gridLine
        : context.strong.withValues(alpha: 0.55);

    if (style == 'line') {
      return Center(
        child: Container(
          height: 1.5,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );
    }
    if (style == 'dots') {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var dot = 0; dot < 3; dot++)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
              ),
          ],
        ),
      );
    }

    // Nothing to show, so it shows nothing — except while the board is being
    // arranged, where a gap still has to be findable.
    return context.isEditable
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
            ),
            child: const SizedBox.expand(),
          )
        : const SizedBox.expand();
  }
}
