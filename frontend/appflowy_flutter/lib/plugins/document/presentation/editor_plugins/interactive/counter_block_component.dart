import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_text.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// How a counter is laid out.
enum CounterStyle {
  /// A soft card with the figure between the two controls.
  card,

  /// The same arrangement with no surface under it.
  plain,

  /// A capsule, for a counter that sits beside a sentence.
  pill,

  /// The figure above, the controls beneath it.
  stacked;

  static CounterStyle fromValue(Object? value) =>
      CounterStyle.values.firstWhere(
        (s) => s.name == value,
        orElse: () => CounterStyle.card,
      );

  String get label => switch (this) {
        CounterStyle.card => LocaleKeys.interactive_counter_styleCard.tr(),
        CounterStyle.plain => LocaleKeys.interactive_counter_stylePlain.tr(),
        CounterStyle.pill => LocaleKeys.interactive_counter_stylePill.tr(),
        CounterStyle.stacked =>
          LocaleKeys.interactive_counter_styleStacked.tr(),
      };

  IconData get icon => switch (this) {
        CounterStyle.card => Icons.crop_square_rounded,
        CounterStyle.plain => Icons.remove_rounded,
        CounterStyle.pill => Icons.crop_16_9_rounded,
        CounterStyle.stacked => Icons.view_agenda_rounded,
      };

  bool get hasSurface => this != CounterStyle.plain;
}

class CounterBlockKeys {
  const CounterBlockKeys._();

  static const String type = 'interactive_counter';

  static const String value = 'value';
  static const String minimum = 'minimum';
  static const String maximum = 'maximum';
  static const String step = 'step';

  /// The value the reset action returns to.
  static const String initial = 'initial';

  static const String prefix = 'prefix';
  static const String suffix = 'suffix';

  /// One of [CounterStyle].
  static const String style = 'style';

  /// One of [InteractiveShape].
  static const String shape = 'shape';
}

Node counterNode({
  double value = 0,
  String label = '',
  InteractiveAccent accent = InteractiveAccent.neutral,
}) =>
    Node(
      type: CounterBlockKeys.type,
      attributes: {
        CounterBlockKeys.value: value,
        CounterBlockKeys.initial: value,
        CounterBlockKeys.step: 1,
        InteractiveBlockKeys.label: label,
        InteractiveBlockKeys.accent: accent.name,
        InteractiveBlockKeys.size: InteractiveSize.compact.name,
      },
    );

class CounterBlockComponentBuilder extends BlockComponentBuilder {
  CounterBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CounterBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class CounterBlockComponent extends BlockComponentStatefulWidget {
  const CounterBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CounterBlockComponent> createState() => CounterBlockComponentState();
}

class CounterBlockComponentState extends State<CounterBlockComponent>
    with BlockComponentConfigurable, InteractiveBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  /// The value shown while a run of taps is still settling into the document.
  double? _live;
  Timer? _commit;

  double get _value =>
      _live ?? doubleAttribute(CounterBlockKeys.value, fallback: 0);

  double get _step {
    final step = doubleAttribute(CounterBlockKeys.step, fallback: 1);
    return step == 0 ? 1 : step;
  }

  double? get _minimum {
    final stored = node.attributes[CounterBlockKeys.minimum];
    return stored is num ? stored.toDouble() : null;
  }

  double? get _maximum {
    final stored = node.attributes[CounterBlockKeys.maximum];
    return stored is num ? stored.toDouble() : null;
  }

  bool get _canDecrease => _minimum == null || _value - _step >= _minimum!;

  bool get _canIncrease => _maximum == null || _value + _step <= _maximum!;

  CounterStyle get _style =>
      CounterStyle.fromValue(node.attributes[CounterBlockKeys.style]);

  InteractiveShape get _shape =>
      InteractiveShape.fromValue(node.attributes[CounterBlockKeys.shape]);

  @override
  void dispose() {
    _commit?.cancel();
    super.dispose();
  }

  /// A run of taps is one transaction, not one per press.
  void _nudge(double delta) {
    if (!editable) {
      return;
    }
    var next = _value + delta;
    final minimum = _minimum;
    final maximum = _maximum;
    if (minimum != null) {
      next = next < minimum ? minimum : next;
    }
    if (maximum != null) {
      next = next > maximum ? maximum : next;
    }
    if (next == _value) {
      return;
    }
    setState(() => _live = next);
    _commit?.cancel();
    _commit = Timer(const Duration(milliseconds: 320), () {
      _commit = null;
      final value = _live;
      _live = null;
      if (value != null) {
        unawaited(writeAttributes({CounterBlockKeys.value: value}));
      }
    });
  }

  Future<void> _askForNumber(
    String key,
    String title,
    double? current, {
    bool clearable = false,
  }) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: current == null ? '' : formatCounterValue(current),
    );
    if (answer == null) {
      return;
    }
    final trimmed = answer.trim();
    if (trimmed.isEmpty && clearable) {
      await writeAttributes({key: null});
      return;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null) {
      return;
    }
    await writeAttributes({key: parsed});
  }

  Future<void> _askForText(String key, String title) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: stringAttribute(key),
    );
    if (answer == null) {
      return;
    }
    await writeAttributes({key: answer.trim().isEmpty ? null : answer.trim()});
  }

  List<AppMenuEntry> _menu() => interactiveMenuEntries(
        extra: [
          AppMenuItem(
            label: LocaleKeys.interactive_menu_style.tr(),
            icon: Icons.style_rounded,
            subtitle: _style.label,
            submenu: [
              for (final style in CounterStyle.values)
                AppMenuItem(
                  label: style.label,
                  icon: style.icon,
                  selected: style == _style,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({CounterBlockKeys.style: style.name}),
                  ),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_menu_shape.tr(),
            icon: Icons.rounded_corner_rounded,
            enabled: _style.hasSurface,
            submenu: [
              for (final shape in InteractiveShape.values)
                AppMenuItem(
                  label: interactiveShapeLabel(shape),
                  selected: shape == _shape,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({CounterBlockKeys.shape: shape.name}),
                  ),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_counter_reset.tr(),
            icon: Icons.restart_alt_rounded,
            enabled: editable,
            onSelected: () {
              _commit?.cancel();
              _live = null;
              unawaited(
                writeAttributes({
                  CounterBlockKeys.value:
                      doubleAttribute(CounterBlockKeys.initial, fallback: 0),
                }),
              );
            },
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_counter_configure.tr(),
            icon: Icons.tune_rounded,
            submenu: [
              AppMenuItem(
                label: LocaleKeys.interactive_counter_setValue.tr(),
                icon: Icons.pin_rounded,
                enabled: editable,
                onSelected: () => unawaited(
                  _askForNumber(
                    CounterBlockKeys.value,
                    LocaleKeys.interactive_counter_setValue.tr(),
                    _value,
                  ),
                ),
              ),
              AppMenuItem(
                label: LocaleKeys.interactive_counter_setStep.tr(),
                icon: Icons.linear_scale_rounded,
                enabled: editable,
                onSelected: () => unawaited(
                  _askForNumber(
                    CounterBlockKeys.step,
                    LocaleKeys.interactive_counter_setStep.tr(),
                    _step,
                  ),
                ),
              ),
              AppMenuItem(
                label: LocaleKeys.interactive_counter_setMinimum.tr(),
                icon: Icons.south_rounded,
                enabled: editable,
                onSelected: () => unawaited(
                  _askForNumber(
                    CounterBlockKeys.minimum,
                    LocaleKeys.interactive_counter_setMinimum.tr(),
                    _minimum,
                    clearable: true,
                  ),
                ),
              ),
              AppMenuItem(
                label: LocaleKeys.interactive_counter_setMaximum.tr(),
                icon: Icons.north_rounded,
                enabled: editable,
                onSelected: () => unawaited(
                  _askForNumber(
                    CounterBlockKeys.maximum,
                    LocaleKeys.interactive_counter_setMaximum.tr(),
                    _maximum,
                    clearable: true,
                  ),
                ),
              ),
              AppMenuItem(
                label: LocaleKeys.interactive_counter_setPrefix.tr(),
                icon: Icons.first_page_rounded,
                enabled: editable,
                onSelected: () => unawaited(
                  _askForText(
                    CounterBlockKeys.prefix,
                    LocaleKeys.interactive_counter_setPrefix.tr(),
                  ),
                ),
              ),
              AppMenuItem(
                label: LocaleKeys.interactive_counter_setSuffix.tr(),
                icon: Icons.last_page_rounded,
                enabled: editable,
                onSelected: () => unawaited(
                  _askForText(
                    CounterBlockKeys.suffix,
                    LocaleKeys.interactive_counter_setSuffix.tr(),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final tone = accent.resolve(palette);
    final style = _style;

    final minus = InteractiveIconButton(
      icon: Icons.remove_rounded,
      tooltip: LocaleKeys.interactive_counter_decrease.tr(),
      palette: palette,
      accent: tone.strong,
      size: 30,
      iconSize: 17,
      onPressed: editable && _canDecrease ? () => _nudge(-_step) : null,
    );
    final plus = InteractiveIconButton(
      icon: Icons.add_rounded,
      tooltip: LocaleKeys.interactive_counter_increase.tr(),
      palette: palette,
      accent: tone.strong,
      size: 30,
      iconSize: 17,
      onPressed: editable && _canIncrease ? () => _nudge(_step) : null,
    );

    final body = style == CounterStyle.stacked
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFigure(palette),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [minus, const SizedBox(width: 18), plus],
              ),
              const SizedBox(height: 4),
              _buildLabel(palette),
            ],
          )
        : Row(
            children: [
              minus,
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFigure(palette),
                    if (style != CounterStyle.pill) ...[
                      const SizedBox(height: 2),
                      _buildLabel(palette),
                    ],
                  ],
                ),
              ),
              plus,
            ],
          );

    final Widget surface = style.hasSurface
        ? Container(
            padding: EdgeInsets.symmetric(
              horizontal: style == CounterStyle.pill ? 6 : 10,
              vertical: style == CounterStyle.pill ? 5 : 12,
            ),
            decoration: BoxDecoration(
              color: tone.surface,
              borderRadius: BorderRadius.circular(
                style == CounterStyle.pill
                    ? 999
                    : _shape.radiusFor(InteractiveMetrics.blockRadius * 2),
              ),
              border: Border.all(color: tone.border.withValues(alpha: 0.7)),
            ),
            child: body,
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: body,
          );

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel:
            '${LocaleKeys.interactive_counter_name.tr()} ${formatCounterValue(_value)}',
        menuBuilder: _menu,
        // The plus already occupies the top-right corner, so the hover
        // controls float clear of the block instead of over it.
        placement: InteractiveControlsPlacement.outside,
        child: surface,
      ),
    );
  }

  Widget _buildFigure(InteractivePalette palette) {
    final prefix = stringAttribute(CounterBlockKeys.prefix);
    final suffix = stringAttribute(CounterBlockKeys.suffix);
    final compact = _style == CounterStyle.pill;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (prefix.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Text(
              prefix,
              style: InteractiveType.caption(palette).copyWith(fontSize: 13),
            ),
          ),
        AnimatedSwitcher(
          duration: InteractiveMetrics.reveal,
          switchInCurve: InteractiveMetrics.curve,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            formatCounterValue(_value),
            key: ValueKey(_value),
            style: InteractiveType.figure(
              palette,
              size: compact ? 18 : (_style == CounterStyle.stacked ? 34 : 26),
            ),
          ),
        ),
        if (suffix.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text(
              suffix,
              style: InteractiveType.caption(palette).copyWith(fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildLabel(InteractivePalette palette) => InteractiveFocusGuard(
        child: InteractiveEditableText(
          value: blockLabel,
          enabled: editable,
          palette: palette,
          textAlign: TextAlign.center,
          hint: LocaleKeys.interactive_counter_labelHint.tr(),
          style: InteractiveType.caption(palette),
          onChanged: (value) =>
              writeAttributes({InteractiveBlockKeys.label: value}),
        ),
      );
}

/// Whole numbers read as whole numbers; only a real fraction shows a point.
String formatCounterValue(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
          RegExp(r'\.$'),
          '',
        );
