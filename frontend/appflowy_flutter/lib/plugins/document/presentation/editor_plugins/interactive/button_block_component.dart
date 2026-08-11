import 'dart:async';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_text.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_view_picker.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// What a button block does when it is pressed.
///
/// Every one of these is something the application can genuinely carry out;
/// nothing here is a label for a feature that does not exist.
enum InteractiveButtonAction {
  /// Press it and nothing happens — useful while a page is being drafted.
  none,

  /// Open a page, a file or a collection in the workspace.
  openView,

  /// Open an address in the browser.
  openUrl,

  /// Put configured text on the clipboard.
  copyText,

  /// Open the reminder composer, seeded with the button's label.
  setReminder;

  static InteractiveButtonAction fromValue(Object? value) =>
      InteractiveButtonAction.values.firstWhere(
        (a) => a.name == value,
        orElse: () => InteractiveButtonAction.none,
      );

  String get label => switch (this) {
        InteractiveButtonAction.none =>
          LocaleKeys.interactive_button_actionNone.tr(),
        InteractiveButtonAction.openView =>
          LocaleKeys.interactive_button_actionOpenView.tr(),
        InteractiveButtonAction.openUrl =>
          LocaleKeys.interactive_button_actionOpenUrl.tr(),
        InteractiveButtonAction.copyText =>
          LocaleKeys.interactive_button_actionCopy.tr(),
        InteractiveButtonAction.setReminder =>
          LocaleKeys.interactive_button_actionReminder.tr(),
      };

  IconData get icon => switch (this) {
        InteractiveButtonAction.none => Icons.block_rounded,
        InteractiveButtonAction.openView => Icons.description_rounded,
        InteractiveButtonAction.openUrl => Icons.link_rounded,
        InteractiveButtonAction.copyText => Icons.content_copy_rounded,
        InteractiveButtonAction.setReminder => Icons.notifications_rounded,
      };
}

class ButtonBlockKeys {
  const ButtonBlockKeys._();

  static const String type = 'interactive_button';

  static const String label = 'label';

  /// One of [InteractiveEmphasis].
  static const String style = 'style';

  /// One of [InteractiveButtonAction].
  static const String action = 'action';

  /// The address, the view id or the text the action works on.
  static const String target = 'target';

  /// A readable name for [target] — the page's title, so the menu can say
  /// which page without a round trip.
  static const String targetName = 'target_name';

  /// The leading glyph, named from [interactiveButtonIcons].
  static const String icon = 'icon';

  /// One of [InteractiveControlSize].
  static const String buttonSize = 'button_size';

  /// One of [InteractiveShape].
  static const String shape = 'shape';

  static const String disabled = 'disabled';
}

/// The glyphs a button can wear.
///
/// A short, curated set from the application's own rounded family — an icon
/// picker over thousands of shapes is not what a button needs.
const Map<String, IconData> interactiveButtonIcons = {
  'none': Icons.remove_rounded,
  'arrow': Icons.arrow_forward_rounded,
  'open': Icons.open_in_new_rounded,
  'play': Icons.play_arrow_rounded,
  'check': Icons.check_rounded,
  'plus': Icons.add_rounded,
  'bolt': Icons.bolt_rounded,
  'bell': Icons.notifications_rounded,
  'link': Icons.link_rounded,
  'copy': Icons.content_copy_rounded,
  'star': Icons.star_rounded,
  'page': Icons.description_rounded,
};

Node buttonNode({
  String label = '',
  InteractiveEmphasis style = InteractiveEmphasis.primary,
  InteractiveButtonAction action = InteractiveButtonAction.none,
}) =>
    Node(
      type: ButtonBlockKeys.type,
      attributes: {
        ButtonBlockKeys.label: label.isEmpty
            ? LocaleKeys.interactive_button_defaultLabel.tr()
            : label,
        ButtonBlockKeys.style: style.name,
        ButtonBlockKeys.action: action.name,
        ButtonBlockKeys.icon: 'arrow',
        InteractiveBlockKeys.size: InteractiveSize.compact.name,
      },
    );

class ButtonBlockComponentBuilder extends BlockComponentBuilder {
  ButtonBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ButtonBlockComponent(
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

class ButtonBlockComponent extends BlockComponentStatefulWidget {
  const ButtonBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ButtonBlockComponent> createState() => ButtonBlockComponentState();
}

class ButtonBlockComponentState extends State<ButtonBlockComponent>
    with BlockComponentConfigurable, InteractiveBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  bool _renaming = false;

  String get _label => stringAttribute(
        ButtonBlockKeys.label,
        fallback: LocaleKeys.interactive_button_defaultLabel.tr(),
      );

  InteractiveEmphasis get _style => InteractiveEmphasis.values.firstWhere(
        (e) => e.name == node.attributes[ButtonBlockKeys.style],
        orElse: () => InteractiveEmphasis.primary,
      );

  InteractiveButtonAction get _action => InteractiveButtonAction.fromValue(
      node.attributes[ButtonBlockKeys.action]);

  IconData? get _icon =>
      interactiveButtonIcons[stringAttribute(ButtonBlockKeys.icon)];

  InteractiveControlSize get _buttonSize => InteractiveControlSize.fromValue(
        node.attributes[ButtonBlockKeys.buttonSize],
      );

  InteractiveShape get _shape =>
      InteractiveShape.fromValue(node.attributes[ButtonBlockKeys.shape]);

  bool get _disabled => boolAttribute(ButtonBlockKeys.disabled);

  /// Begin renaming in place. Also used by the slash menu, so `/button` lands
  /// with the label ready to type.
  void beginRename() {
    if (!editable || !mounted) {
      return;
    }
    setState(() => _renaming = true);
  }

  Future<void> _run() async {
    if (_disabled) {
      return;
    }
    final target = stringAttribute(ButtonBlockKeys.target);
    switch (_action) {
      case InteractiveButtonAction.none:
        return;
      case InteractiveButtonAction.openUrl:
        if (target.isNotEmpty) {
          await afLaunchUrlString(target, context: context);
        }
      case InteractiveButtonAction.openView:
        if (target.isEmpty) {
          return;
        }
        final result = await ViewBackendService.getView(target);
        if (!mounted) {
          return;
        }
        result.fold(
          (view) => context.read<TabsBloc>().openPlugin(view),
          (_) => showToastNotification(
            message: LocaleKeys.interactive_button_targetMissing.tr(),
            type: ToastificationType.warning,
          ),
        );
      case InteractiveButtonAction.copyText:
        await Clipboard.setData(ClipboardData(text: target));
        if (mounted) {
          showToastNotification(
            message: LocaleKeys.interactive_button_copied.tr(),
          );
        }
      case InteractiveButtonAction.setReminder:
        await showReminderComposer(
          context,
          initialText: _label,
          kind: ReminderKind.block,
        );
    }
  }

  Future<void> _configure(InteractiveButtonAction action) async {
    switch (action) {
      case InteractiveButtonAction.none:
      case InteractiveButtonAction.setReminder:
        await writeAttributes({
          ButtonBlockKeys.action: action.name,
          ButtonBlockKeys.target: null,
          ButtonBlockKeys.targetName: null,
        });
      case InteractiveButtonAction.openView:
        final view = await showInteractiveViewPicker(context);
        if (view == null) {
          return;
        }
        await writeAttributes({
          ButtonBlockKeys.action: action.name,
          ButtonBlockKeys.target: view.id,
          ButtonBlockKeys.targetName: view.name,
        });
      case InteractiveButtonAction.openUrl:
        final url = await showAFTextFieldDialog(
          context: context,
          title: LocaleKeys.interactive_button_actionOpenUrl.tr(),
          initialValue: stringAttribute(ButtonBlockKeys.target),
          hintText: 'https://',
        );
        if (url == null || url.trim().isEmpty) {
          return;
        }
        await writeAttributes({
          ButtonBlockKeys.action: action.name,
          ButtonBlockKeys.target: url.trim(),
          ButtonBlockKeys.targetName: null,
        });
      case InteractiveButtonAction.copyText:
        final text = await showAFTextFieldDialog(
          context: context,
          title: LocaleKeys.interactive_button_actionCopy.tr(),
          initialValue: stringAttribute(ButtonBlockKeys.target),
        );
        if (text == null) {
          return;
        }
        await writeAttributes({
          ButtonBlockKeys.action: action.name,
          ButtonBlockKeys.target: text,
          ButtonBlockKeys.targetName: null,
        });
    }
  }

  List<AppMenuEntry> _menu() => interactiveMenuEntries(
        // A button hugs its label, so the block width means nothing here —
        // the size that matters is the control's own.
        showSize: false,
        extra: [
          AppMenuItem(
            label: LocaleKeys.interactive_button_rename.tr(),
            icon: Icons.text_fields_rounded,
            enabled: editable,
            onSelected: beginRename,
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_menu_size.tr(),
            icon: Icons.format_size_rounded,
            submenu: [
              for (final size in InteractiveControlSize.values)
                AppMenuItem(
                  label: interactiveControlSizeLabel(size),
                  selected: size == _buttonSize,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({ButtonBlockKeys.buttonSize: size.name}),
                  ),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_menu_shape.tr(),
            icon: Icons.rounded_corner_rounded,
            submenu: [
              for (final shape in InteractiveShape.values)
                AppMenuItem(
                  label: interactiveShapeLabel(shape),
                  icon: switch (shape) {
                    InteractiveShape.rounded => Icons.crop_square_rounded,
                    InteractiveShape.pill => Icons.crop_16_9_rounded,
                    InteractiveShape.square => Icons.check_box_outline_blank,
                  },
                  selected: shape == _shape,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({ButtonBlockKeys.shape: shape.name}),
                  ),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_button_style.tr(),
            icon: Icons.brush_rounded,
            submenu: [
              for (final style in InteractiveEmphasis.values)
                AppMenuItem(
                  label: _styleLabel(style),
                  icon: _styleIcon(style),
                  selected: style == _style,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({ButtonBlockKeys.style: style.name}),
                  ),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_button_icon.tr(),
            icon: Icons.emoji_symbols_rounded,
            submenu: [
              for (final entry in interactiveButtonIcons.entries)
                AppMenuItem(
                  label: entry.key,
                  icon: entry.value,
                  selected: entry.key == stringAttribute(ButtonBlockKeys.icon),
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({ButtonBlockKeys.icon: entry.key}),
                  ),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_button_action.tr(),
            icon: Icons.bolt_rounded,
            subtitle: _action.label,
            submenu: [
              for (final action in InteractiveButtonAction.values)
                AppMenuItem(
                  label: action.label,
                  icon: action.icon,
                  selected: action == _action,
                  enabled: editable,
                  onSelected: () => unawaited(_configure(action)),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_button_disabled.tr(),
            icon: _disabled
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            enabled: editable,
            onSelected: () => unawaited(
              writeAttributes({ButtonBlockKeys.disabled: !_disabled}),
            ),
          ),
        ],
      );

  static String _styleLabel(InteractiveEmphasis style) => switch (style) {
        InteractiveEmphasis.primary =>
          LocaleKeys.interactive_button_stylePrimary.tr(),
        InteractiveEmphasis.secondary =>
          LocaleKeys.interactive_button_styleSecondary.tr(),
        InteractiveEmphasis.ghost =>
          LocaleKeys.interactive_button_styleGhost.tr(),
        InteractiveEmphasis.subtle =>
          LocaleKeys.interactive_button_styleSubtle.tr(),
        InteractiveEmphasis.danger =>
          LocaleKeys.interactive_button_styleDanger.tr(),
      };

  static IconData _styleIcon(InteractiveEmphasis style) => switch (style) {
        InteractiveEmphasis.primary => Icons.circle_rounded,
        InteractiveEmphasis.secondary => Icons.circle_outlined,
        InteractiveEmphasis.ghost => Icons.blur_on_rounded,
        InteractiveEmphasis.subtle => Icons.water_drop_outlined,
        InteractiveEmphasis.danger => Icons.warning_amber_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);

    final Widget control = _renaming
        ? InteractiveFocusGuard(
            child: InteractiveFieldSurface(
              focused: true,
              palette: palette,
              child: Center(
                child: InteractiveEditableText(
                  value: _label,
                  autofocus: true,
                  palette: palette,
                  style: InteractiveType.strong(palette, size: 13.5),
                  onChanged: (value) => writeAttributes({
                    ButtonBlockKeys.label: value.trim().isEmpty
                        ? LocaleKeys.interactive_button_defaultLabel.tr()
                        : value.trim(),
                  }),
                  onSubmitted: (_) => setState(() => _renaming = false),
                  onFocusChanged: (focused) {
                    if (!focused && mounted) {
                      setState(() => _renaming = false);
                    }
                  },
                ),
              ),
            ),
          )
        : InteractiveButton(
            label: _label,
            icon: _icon,
            emphasis: _style,
            accent: accent == InteractiveAccent.neutral ? null : accent,
            size: _buttonSize,
            shape: _shape,
            palette: palette,
            onPressed: _disabled ? null : () => unawaited(_run()),
          );

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel: '${LocaleKeys.interactive_button_name.tr()}: $_label',
        controlsOffset: const Offset(-2, -6),
        menuBuilder: _menu,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: control,
          ),
        ),
      ),
    );
  }
}
