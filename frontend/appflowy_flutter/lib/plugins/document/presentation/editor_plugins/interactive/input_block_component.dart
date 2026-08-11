import 'dart:async';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_text.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What an input bar refuses to accept.
enum InputValidation {
  none,
  number,
  email,
  url;

  static InputValidation fromValue(Object? value) =>
      InputValidation.values.firstWhere(
        (v) => v.name == value,
        orElse: () => InputValidation.none,
      );

  String get label => switch (this) {
        InputValidation.none => LocaleKeys.interactive_input_anyText.tr(),
        InputValidation.number => LocaleKeys.interactive_input_number.tr(),
        InputValidation.email => LocaleKeys.interactive_input_email.tr(),
        InputValidation.url => LocaleKeys.interactive_input_url.tr(),
      };

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$');

  /// Null when the value is acceptable, a sentence when it is not.
  String? check(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    return switch (this) {
      InputValidation.none => null,
      InputValidation.number => double.tryParse(value.trim()) == null
          ? LocaleKeys.interactive_input_notNumber.tr()
          : null,
      InputValidation.email => _email.hasMatch(value.trim())
          ? null
          : LocaleKeys.interactive_input_notEmail.tr(),
      InputValidation.url =>
        (Uri.tryParse(value.trim())?.hasAbsolutePath ?? false) &&
                value.trim().contains('.')
            ? null
            : LocaleKeys.interactive_input_notUrl.tr(),
    };
  }
}

/// What pressing Enter, or the trailing button, does with the value.
enum InputSubmitAction {
  none,
  copy,
  openUrl;

  static InputSubmitAction fromValue(Object? value) =>
      InputSubmitAction.values.firstWhere(
        (a) => a.name == value,
        orElse: () => InputSubmitAction.none,
      );

  String get label => switch (this) {
        InputSubmitAction.none => LocaleKeys.interactive_input_submitNone.tr(),
        InputSubmitAction.copy => LocaleKeys.interactive_input_submitCopy.tr(),
        InputSubmitAction.openUrl =>
          LocaleKeys.interactive_input_submitOpen.tr(),
      };

  IconData get icon => switch (this) {
        InputSubmitAction.none => Icons.block_rounded,
        InputSubmitAction.copy => Icons.content_copy_rounded,
        InputSubmitAction.openUrl => Icons.open_in_new_rounded,
      };
}

class InputBlockKeys {
  const InputBlockKeys._();

  static const String type = 'interactive_input';

  /// What has been typed. Persisted, so a page keeps its answers.
  static const String value = 'value';

  static const String placeholder = 'placeholder';

  /// One of [InputValidation].
  static const String validation = 'validation';

  /// One of [InputSubmitAction].
  static const String submit = 'submit';

  /// A leading glyph named from [interactiveInputIcons].
  static const String icon = 'icon';
}

const Map<String, IconData> interactiveInputIcons = {
  'none': Icons.remove_rounded,
  'edit': Icons.edit_rounded,
  'person': Icons.person_rounded,
  'mail': Icons.alternate_email_rounded,
  'link': Icons.link_rounded,
  'number': Icons.tag_rounded,
  'calendar': Icons.calendar_today_rounded,
  'note': Icons.sticky_note_2_rounded,
};

Node inputNode({String label = '', String placeholder = ''}) => Node(
      type: InputBlockKeys.type,
      attributes: {
        InteractiveBlockKeys.label: label,
        InputBlockKeys.placeholder: placeholder,
        InputBlockKeys.value: '',
        InputBlockKeys.icon: 'edit',
        InteractiveBlockKeys.size: InteractiveSize.medium.name,
      },
    );

class InputBlockComponentBuilder extends BlockComponentBuilder {
  InputBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return InputBlockComponent(
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

class InputBlockComponent extends BlockComponentStatefulWidget {
  const InputBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<InputBlockComponent> createState() => InputBlockComponentState();
}

class InputBlockComponentState extends State<InputBlockComponent>
    with BlockComponentConfigurable, InteractiveBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'interactive input');

  bool _focused = false;
  bool _hovered = false;
  String _live = '';

  InputValidation get _validation =>
      InputValidation.fromValue(node.attributes[InputBlockKeys.validation]);

  InputSubmitAction get _submit =>
      InputSubmitAction.fromValue(node.attributes[InputBlockKeys.submit]);

  @override
  void initState() {
    super.initState();
    _live = stringAttribute(InputBlockKeys.value);
    _controller.text = _live;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Opens the field. `/input` calls it so the block lands ready to type.
  void focusField() => _focus.requestFocus();

  Future<void> _runSubmit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    switch (_submit) {
      case InputSubmitAction.none:
        return;
      case InputSubmitAction.copy:
        await Clipboard.setData(ClipboardData(text: value));
        if (mounted) {
          showToastNotification(
            message: LocaleKeys.interactive_button_copied.tr(),
          );
        }
      case InputSubmitAction.openUrl:
        await afLaunchUrlString(value, context: context);
    }
  }

  List<AppMenuEntry> _menu() => interactiveMenuEntries(
        extra: [
          AppMenuItem(
            label: LocaleKeys.interactive_input_setPlaceholder.tr(),
            icon: Icons.short_text_rounded,
            enabled: editable,
            onSelected: () => unawaited(_askForPlaceholder()),
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_input_validation.tr(),
            icon: Icons.rule_rounded,
            subtitle: _validation.label,
            submenu: [
              for (final value in InputValidation.values)
                AppMenuItem(
                  label: value.label,
                  selected: value == _validation,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({InputBlockKeys.validation: value.name}),
                  ),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_input_submitAction.tr(),
            icon: Icons.keyboard_return_rounded,
            subtitle: _submit.label,
            submenu: [
              for (final value in InputSubmitAction.values)
                AppMenuItem(
                  label: value.label,
                  icon: value.icon,
                  selected: value == _submit,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({InputBlockKeys.submit: value.name}),
                  ),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_input_icon.tr(),
            icon: Icons.emoji_symbols_rounded,
            submenu: [
              for (final entry in interactiveInputIcons.entries)
                AppMenuItem(
                  label: entry.key,
                  icon: entry.value,
                  selected: entry.key == stringAttribute(InputBlockKeys.icon),
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({InputBlockKeys.icon: entry.key}),
                  ),
                ),
            ],
          ),
        ],
      );

  Future<void> _askForPlaceholder() async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: LocaleKeys.interactive_input_setPlaceholder.tr(),
      initialValue: stringAttribute(InputBlockKeys.placeholder),
    );
    if (answer == null) {
      return;
    }
    await writeAttributes({InputBlockKeys.placeholder: answer});
  }

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final tone = accent.resolve(palette);
    final error = _validation.check(_live);
    final icon = interactiveInputIcons[stringAttribute(InputBlockKeys.icon)];

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel: LocaleKeys.interactive_input_name.tr(),
        menuBuilder: _menu,
        child: InteractiveFocusGuard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (blockLabel.isNotEmpty || editable) ...[
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 12,
                      decoration: BoxDecoration(
                        color: tone.strong.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InteractiveEditableText(
                        value: blockLabel,
                        enabled: editable,
                        palette: palette,
                        hint: LocaleKeys.interactive_input_labelHint.tr(),
                        style: InteractiveType.strong(palette, size: 12.5),
                        onChanged: (value) => writeAttributes(
                          {InteractiveBlockKeys.label: value},
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              MouseRegion(
                opaque: false,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: InteractiveFieldSurface(
                  focused: _focused,
                  hovered: _hovered,
                  palette: palette,
                  height: 42,
                  radius: 14,
                  fill: accent == InteractiveAccent.neutral
                      ? null
                      : Color.alphaBlend(
                          tone.strong.withValues(
                            alpha: palette.isDark ? 0.10 : 0.055,
                          ),
                          palette.surface,
                        ),
                  accent: error == null
                      ? tone.strong
                      : InteractiveAccent.red.resolve(palette).strong,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      if (icon != null && icon != Icons.remove_rounded) ...[
                        AnimatedContainer(
                          duration: InteractiveMetrics.hover,
                          curve: InteractiveMetrics.curve,
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: tone.strong.withValues(
                              alpha: _focused ? 0.18 : 0.10,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            icon,
                            size: 15,
                            color: tone.strong,
                          ),
                        ),
                        const SizedBox(width: 9),
                      ] else
                        const SizedBox(width: 3),
                      Expanded(
                        child: InteractiveEditableText(
                          controller: _controller,
                          focusNode: _focus,
                          value: stringAttribute(InputBlockKeys.value),
                          palette: palette,
                          hint: stringAttribute(
                            InputBlockKeys.placeholder,
                            fallback:
                                LocaleKeys.interactive_input_placeholder.tr(),
                          ),
                          style: InteractiveType.body(palette)
                              .copyWith(fontSize: 14),
                          onLiveChanged: (value) =>
                              setState(() => _live = value),
                          onFocusChanged: (value) =>
                              setState(() => _focused = value),
                          onChanged: (value) =>
                              writeAttributes({InputBlockKeys.value: value}),
                          onSubmitted: (_) => unawaited(_runSubmit()),
                        ),
                      ),
                      if (_live.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        InteractiveIconButton(
                          icon: Icons.cancel_rounded,
                          tooltip: LocaleKeys.interactive_input_clear.tr(),
                          palette: palette,
                          size: 24,
                          iconSize: 15,
                          onPressed: () {
                            _controller.clear();
                            setState(() => _live = '');
                            unawaited(
                              writeAttributes({InputBlockKeys.value: ''}),
                            );
                          },
                        ),
                      ],
                      if (_submit != InputSubmitAction.none) ...[
                        const SizedBox(width: 4),
                        InteractiveIconButton(
                          icon: _submit.icon,
                          tooltip: _submit.label,
                          palette: palette,
                          accent: tone.strong,
                          size: 28,
                          onPressed: _live.trim().isEmpty
                              ? null
                              : () => unawaited(_runSubmit()),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: InteractiveMetrics.reveal,
                curve: InteractiveMetrics.curve,
                alignment: Alignment.topCenter,
                child: error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 6, left: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 13,
                              color:
                                  InteractiveAccent.red.resolve(palette).strong,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                error,
                                style:
                                    InteractiveType.caption(palette).copyWith(
                                  color: InteractiveAccent.red
                                      .resolve(palette)
                                      .strong,
                                ),
                              ),
                            ),
                          ],
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
