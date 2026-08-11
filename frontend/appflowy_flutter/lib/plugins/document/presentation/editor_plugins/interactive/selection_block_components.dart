import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_option.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_text.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Attribute names the three selection blocks share.
abstract final class SelectionBlockKeys {
  /// The choices, stored as a list of maps.
  static const String options = 'options';

  /// The chosen option ids. A single-choice block keeps at most one.
  static const String selected = 'selected';
}

class SelectorBlockKeys {
  const SelectorBlockKeys._();

  static const String type = 'interactive_selector';
}

class RadioGroupBlockKeys {
  const RadioGroupBlockKeys._();

  static const String type = 'interactive_radio_group';
}

class MultiSelectBlockKeys {
  const MultiSelectBlockKeys._();

  static const String type = 'interactive_multi_select';
}

Node _selectionNode(String type, String label, InteractiveSize size) => Node(
      type: type,
      attributes: {
        SelectionBlockKeys.options:
            encodeInteractiveOptions(defaultInteractiveOptions()),
        SelectionBlockKeys.selected: const <String>[],
        InteractiveBlockKeys.label: label,
        InteractiveBlockKeys.size: size.name,
      },
    );

Node selectorNode({String label = ''}) =>
    _selectionNode(SelectorBlockKeys.type, label, InteractiveSize.compact);

Node radioGroupNode({String label = ''}) =>
    _selectionNode(RadioGroupBlockKeys.type, label, InteractiveSize.medium);

Node multiSelectNode({String label = ''}) =>
    _selectionNode(MultiSelectBlockKeys.type, label, InteractiveSize.medium);

/// What the three selection blocks have in common: the option list, what is
/// chosen and the rows that let both be changed.
mixin _SelectionBlockMixin<T extends StatefulWidget>
    on State<T>, InteractiveBlockMixin<T> {
  bool get allowsMultiple;

  List<InteractiveOption> get options =>
      decodeInteractiveOptions(node.attributes[SelectionBlockKeys.options]);

  Set<String> get selected {
    final raw = node.attributes[SelectionBlockKeys.selected];
    if (raw is List) {
      return raw.whereType<String>().toSet();
    }
    if (raw is String && raw.isNotEmpty) {
      return {raw};
    }
    return <String>{};
  }

  List<InteractiveOption> get selectedOptions =>
      options.where((option) => selected.contains(option.id)).toList();

  Future<void> writeSelection(Set<String> ids) {
    final ordered = options
        .where((option) => ids.contains(option.id))
        .map((option) => option.id)
        .toList();
    return writeAttributes({
      SelectionBlockKeys.selected:
          allowsMultiple ? ordered : ordered.take(1).toList(),
    });
  }

  Future<void> writeOptions(List<InteractiveOption> next) {
    final ids = next.map((option) => option.id).toSet();
    return writeAttributes({
      SelectionBlockKeys.options: encodeInteractiveOptions(next),
      SelectionBlockKeys.selected:
          selected.where(ids.contains).toList(growable: false),
    });
  }

  Future<void> addOption(InteractiveOption option) =>
      writeOptions([...options, option]);

  Future<void> _renameOption(InteractiveOption option) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: LocaleKeys.interactive_selector_rename.tr(),
      initialValue: option.label,
    );
    if (answer == null || answer.trim().isEmpty) {
      return;
    }
    await writeOptions([
      for (final current in options)
        current.id == option.id
            ? current.copyWith(label: answer.trim())
            : current,
    ]);
  }

  Future<void> _askForOption() async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: LocaleKeys.interactive_selector_addOption.tr(),
      initialValue: '',
    );
    if (answer == null || answer.trim().isEmpty) {
      return;
    }
    await addOption(
      InteractiveOption(
        id: newInteractiveOptionId(),
        label: answer.trim(),
        accent: InteractiveAccent
            .values[options.length % InteractiveAccent.values.length],
      ),
    );
  }

  /// The "Options" submenu: add one, then one row per option carrying its own
  /// rename / colour / remove.
  AppMenuEntry get optionsMenu => AppMenuItem(
        label: LocaleKeys.interactive_selector_options.tr(),
        icon: Icons.list_rounded,
        submenu: [
          AppMenuItem(
            label: LocaleKeys.interactive_selector_addOption.tr(),
            icon: Icons.add_rounded,
            enabled: editable,
            onSelected: () => unawaited(_askForOption()),
          ),
          if (options.isNotEmpty) const AppMenuSeparator(),
          for (final option in options)
            AppMenuItem(
              label: option.label,
              iconWidget: InteractiveAccentDot(accent: option.accent),
              submenu: [
                AppMenuItem(
                  label: LocaleKeys.interactive_selector_rename.tr(),
                  icon: Icons.text_fields_rounded,
                  enabled: editable,
                  onSelected: () => unawaited(_renameOption(option)),
                ),
                AppMenuItem(
                  label: LocaleKeys.interactive_menu_colour.tr(),
                  icon: Icons.palette_rounded,
                  submenu: [
                    for (final value in InteractiveAccent.values)
                      AppMenuItem(
                        label: interactiveAccentLabel(value),
                        iconWidget: InteractiveAccentDot(accent: value),
                        selected: value == option.accent,
                        enabled: editable,
                        onSelected: () => unawaited(
                          writeOptions([
                            for (final current in options)
                              current.id == option.id
                                  ? current.copyWith(accent: value)
                                  : current,
                          ]),
                        ),
                      ),
                  ],
                ),
                AppMenuItem(
                  label: LocaleKeys.button_delete.tr(),
                  icon: Icons.delete_outline_rounded,
                  destructive: true,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeOptions(
                      options.where((c) => c.id != option.id).toList(),
                    ),
                  ),
                ),
              ],
            ),
        ],
      );

  /// Opens the floating option list under [anchorKey]'s box.
  Future<void> openPicker(GlobalKey anchorKey) async {
    final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final origin = box.localToGlobal(Offset.zero);
    await showInteractiveOptionPicker(
      context: context,
      anchor: origin & box.size,
      options: options,
      selected: selected,
      multiple: allowsMultiple,
      onChanged: (ids) => unawaited(writeSelection(ids)),
      onCreate: editable ? (option) => unawaited(addOption(option)) : null,
      width: box.size.width.clamp(232.0, 360.0),
    );
  }

  /// The caption row every selection block prints above its control.
  Widget buildLabel(InteractivePalette palette) => InteractiveFocusGuard(
        child: InteractiveEditableText(
          value: blockLabel,
          enabled: editable,
          palette: palette,
          hint: LocaleKeys.interactive_selector_labelHint.tr(),
          style: InteractiveType.strong(palette, size: 12.5),
          onChanged: (value) =>
              writeAttributes({InteractiveBlockKeys.label: value}),
        ),
      );
}

// ---------------------------------------------------------------------------
// Selector — one choice, shown in a floating list.
// ---------------------------------------------------------------------------

class SelectorBlockComponentBuilder extends BlockComponentBuilder {
  SelectorBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return SelectorBlockComponent(
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

class SelectorBlockComponent extends BlockComponentStatefulWidget {
  const SelectorBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<SelectorBlockComponent> createState() => SelectorBlockComponentState();
}

class SelectorBlockComponentState extends State<SelectorBlockComponent>
    with
        BlockComponentConfigurable,
        InteractiveBlockMixin,
        _SelectionBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  bool get allowsMultiple => false;

  final GlobalKey _anchor = GlobalKey(debugLabel: 'selector trigger');

  /// Opens the option list. `/select` calls it so the block lands ready.
  void openOptions() => unawaited(openPicker(_anchor));

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final chosen = selectedOptions.firstOrNull;

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel: LocaleKeys.interactive_selector_name.tr(),
        menuBuilder: () => interactiveMenuEntries(
          showAccent: false,
          extra: [optionsMenu],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            buildLabel(palette),
            const SizedBox(height: 7),
            _Trigger(
              key: _anchor,
              palette: palette,
              onTap: openOptions,
              child: chosen == null
                  ? Text(
                      LocaleKeys.interactive_selector_empty.tr(),
                      style: InteractiveType.body(palette)
                          .copyWith(color: palette.textMuted),
                    )
                  : InteractiveChip(
                      label: chosen.label,
                      accent: chosen.accent,
                      palette: palette,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Radio group — one choice, every option on the page.
// ---------------------------------------------------------------------------

class RadioGroupBlockComponentBuilder extends BlockComponentBuilder {
  RadioGroupBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return RadioGroupBlockComponent(
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

class RadioGroupBlockComponent extends BlockComponentStatefulWidget {
  const RadioGroupBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<RadioGroupBlockComponent> createState() =>
      RadioGroupBlockComponentState();
}

class RadioGroupBlockComponentState extends State<RadioGroupBlockComponent>
    with
        BlockComponentConfigurable,
        InteractiveBlockMixin,
        _SelectionBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  bool get allowsMultiple => false;

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final chosen = selected;

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel: LocaleKeys.interactive_radio_name.tr(),
        menuBuilder: () => interactiveMenuEntries(
          showAccent: false,
          extra: [optionsMenu],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            buildLabel(palette),
            const SizedBox(height: 4),
            for (final option in options)
              _RadioRow(
                option: option,
                palette: palette,
                selected: chosen.contains(option.id),
                enabled: editable,
                onTap: () => unawaited(writeSelection({option.id})),
              ),
          ],
        ),
      ),
    );
  }
}

class _RadioRow extends StatefulWidget {
  const _RadioRow({
    required this.option,
    required this.palette,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final InteractiveOption option;
  final InteractivePalette palette;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_RadioRow> createState() => _RadioRowState();
}

class _RadioRowState extends State<_RadioRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final tone = widget.option.accent.resolve(palette);

    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: InteractiveMetrics.hover,
          curve: InteractiveMetrics.curve,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _RadioDot(
                selected: widget.selected,
                accent: tone.strong,
                palette: palette,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  widget.option.label,
                  style: InteractiveType.body(palette).copyWith(
                    color:
                        widget.selected ? palette.text : palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({
    required this.selected,
    required this.accent,
    required this.palette,
  });

  final bool selected;
  final Color accent;
  final InteractivePalette palette;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: InteractiveMetrics.hover,
      curve: InteractiveMetrics.curve,
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? accent : palette.border.withValues(alpha: 0.7),
          width: selected ? 5 : 1.5,
        ),
        color: selected ? palette.raised : Colors.transparent,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-select — several choices, shown as chips.
// ---------------------------------------------------------------------------

class MultiSelectBlockComponentBuilder extends BlockComponentBuilder {
  MultiSelectBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MultiSelectBlockComponent(
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

class MultiSelectBlockComponent extends BlockComponentStatefulWidget {
  const MultiSelectBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MultiSelectBlockComponent> createState() =>
      MultiSelectBlockComponentState();
}

class MultiSelectBlockComponentState extends State<MultiSelectBlockComponent>
    with
        BlockComponentConfigurable,
        InteractiveBlockMixin,
        _SelectionBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  bool get allowsMultiple => true;

  /// How many chips are shown before the rest are counted.
  static const int _shownChips = 4;

  final GlobalKey _anchor = GlobalKey(debugLabel: 'multi select trigger');

  void openOptions() => unawaited(openPicker(_anchor));

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final chosen = selectedOptions;
    final overflow = chosen.length - _shownChips;

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel: LocaleKeys.interactive_multiSelect_name.tr(),
        menuBuilder: () => interactiveMenuEntries(
          showAccent: false,
          extra: [
            optionsMenu,
            AppMenuItem(
              label: LocaleKeys.interactive_selector_clearAll.tr(),
              icon: Icons.backspace_rounded,
              enabled: editable && chosen.isNotEmpty,
              onSelected: () => unawaited(writeSelection(<String>{})),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            buildLabel(palette),
            const SizedBox(height: 7),
            _Trigger(
              key: _anchor,
              palette: palette,
              onTap: openOptions,
              child: chosen.isEmpty
                  ? Text(
                      LocaleKeys.interactive_multiSelect_empty.tr(),
                      style: InteractiveType.body(palette)
                          .copyWith(color: palette.textMuted),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final option in chosen.take(_shownChips))
                          InteractiveChip(
                            label: option.label,
                            accent: option.accent,
                            palette: palette,
                            dense: true,
                            onRemove: editable
                                ? () => unawaited(
                                      writeSelection(
                                        {...selected}..remove(option.id),
                                      ),
                                    )
                                : null,
                          ),
                        if (overflow > 0)
                          Text(
                            '+$overflow',
                            style: InteractiveType.caption(palette),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The soft box a selector or a multi-select is opened from.
class _Trigger extends StatefulWidget {
  const _Trigger({
    super.key,
    required this.palette,
    required this.child,
    required this.onTap,
  });

  final InteractivePalette palette;
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Trigger> createState() => _TriggerState();
}

class _TriggerState extends State<_Trigger> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: InteractiveMetrics.hover,
          curve: InteractiveMetrics.curve,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              palette.hover.withValues(alpha: _hovered ? 1 : 0.75),
              palette.surface,
            ),
            borderRadius: BorderRadius.circular(InteractiveMetrics.fieldRadius),
            border: Border.all(
              color: palette.border.withValues(alpha: _hovered ? 0.44 : 0.30),
            ),
          ),
          child: Row(
            children: [
              Expanded(child: widget.child),
              const SizedBox(width: 8),
              Icon(
                Icons.expand_more_rounded,
                size: 17,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
