import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/text_field.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    this.query,
    this.isLoading = false,
    this.onSubmit,
    this.onChanged,
    this.selectAllOnOpen = true,
    this.hintText,
    this.leadingIcon,
    this.badge,
    this.onTab,
    this.onBackspaceWhenEmpty,
    this.onEscape,
    this.onArrowDown,
    this.focusNode,
    this.controller,
  });

  final String? query;
  final bool isLoading;

  /// A reopened palette selects its last query; a query typed into another
  /// search bar continues with the caret at its end instead.
  final bool selectAllOnOpen;

  /// When supplied, the modal owns dispatch (local contents or metadata).
  /// Backend state is not written back into this field's live draft.
  final ValueChanged<String>? onChanged;

  /// Called when Enter is pressed while the box still has the caret, so the
  /// palette can run whatever it is offering first.
  final VoidCallback? onSubmit;

  /// Replaces the workspace search hint, for a palette narrowed to settings
  /// or holding a conversation.
  final String? hintText;

  /// Replaces the magnifier, such as with the assistant's spark.
  final IconData? leadingIcon;

  /// Sits before the text, naming what the palette is narrowed to.
  final Widget? badge;

  /// Tab while the caret is in the box. Returns whether it was used; when it
  /// was not, Tab moves focus as usual.
  final bool Function()? onTab;

  /// Backspace in an empty box, which steps out of a scope or a list of
  /// choices the way it does in Spotlight.
  final VoidCallback? onBackspaceWhenEmpty;

  /// Escape while the caret is in the box. Returns whether it was used; when
  /// it was not, Escape closes the palette.
  final bool Function()? onEscape;

  /// Down from the box. Without it focus simply moves on.
  final VoidCallback? onArrowDown;

  /// Lets the palette put the caret back in the box after a click elsewhere.
  /// The field still handles its keys through it; the owner disposes it.
  final FocusNode? focusNode;

  /// Lets the palette replace the words itself — clearing them once a
  /// question is asked, or stepping into a list of choices. Without one, a
  /// changed [query] never overwrites what is being typed. The owner disposes
  /// it.
  final TextEditingController? controller;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final FocusNode focusNode;
  late final TextEditingController controller;
  late final bool _ownsFocusNode;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    controller =
        widget.controller ?? TextEditingController(text: widget.query);
    _ownsFocusNode = widget.focusNode == null;
    focusNode = (widget.focusNode ?? FocusNode())..onKeyEvent = _handleKeyEvent;
    focusNode.requestFocus();
    // Update the text selection after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.selection = widget.selectAllOnOpen
          ? TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            )
          : TextSelection.collapsed(offset: controller.text.length);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      final onArrowDown = widget.onArrowDown;
      if (onArrowDown != null) {
        onArrowDown();
      } else {
        node.nextFocus();
      }
      return KeyEventResult.handled;
    }
    final onSubmit = widget.onSubmit;
    if (onSubmit != null &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      onSubmit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab &&
        !HardwareKeyboard.instance.isShiftPressed &&
        (widget.onTab?.call() ?? false)) {
      return KeyEventResult.handled;
    }
    final onBackspace = widget.onBackspaceWhenEmpty;
    if (onBackspace != null &&
        key == LogicalKeyboardKey.backspace &&
        controller.text.isEmpty) {
      onBackspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape &&
        (widget.onEscape?.call() ?? false)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    if (_ownsFocusNode) {
      focusNode.dispose();
    } else if (focusNode.onKeyEvent == _handleKeyEvent) {
      focusNode.onKeyEvent = null;
    }
    if (_ownsController) controller.dispose();
    super.dispose();
  }

  Widget _buildSuffixIcon(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: theme.spacing.m, right: theme.spacing.l),
      child: FlowyTooltip(
        message: LocaleKeys.commandPalette_clearSearchTooltip.tr(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('command-palette-clear-search'),
            behavior: HitTestBehavior.opaque,
            onTap: _clearSearch,
            child: SizedBox.square(
              dimension: 28,
              child: Center(
                child: WorkspaceGlyph.svg(
                  FlowySvgs.search_clear_m,
                  color: AppFlowyTheme.of(context).iconColorScheme.tertiary,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final radius = BorderRadius.circular(theme.spacing.l);
    final workspace =
        context.read<UserWorkspaceBloc?>()?.state.currentWorkspace;

    return Container(
      height: 44,
      margin: EdgeInsets.only(bottom: theme.spacing.m),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final hasText = value.text.trim().isNotEmpty;
          return FlowyTextField(
            focusNode: focusNode,
            cursorHeight: 22,
            controller: controller,
            textStyle: theme.textStyle.heading4
                .standard(color: theme.textColorScheme.primary),
            decoration: InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(vertical: 11, horizontal: 12),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: theme.borderColorScheme.primary),
                borderRadius: radius,
              ),
              isDense: false,
              hintText: widget.hintText ??
                  LocaleKeys.search_searchFieldHint
                      .tr(args: ['${workspace?.name}']),
              hintStyle: theme.textStyle.heading4
                  .standard(color: theme.textColorScheme.tertiary),
              hintMaxLines: 1,
              counterText: "",
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide:
                    BorderSide(color: theme.borderColorScheme.themeThick),
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.leadingIcon == null
                        ? WorkspaceGlyph.svg(
                            FlowySvgs.search_icon_m,
                            color: theme.iconColorScheme.secondary,
                            size: 20,
                          )
                        : WorkspaceGlyph(
                            widget.leadingIcon!,
                            color: WorkspacePalette.of(context).accent,
                            size: 20,
                          ),
                    if (widget.badge != null) ...[
                      const SizedBox(width: 8),
                      widget.badge!,
                    ],
                  ],
                ),
              ),
              prefixIconConstraints: widget.badge == null
                  ? BoxConstraints.loose(Size(40, 20))
                  : BoxConstraints.loose(Size(320, 28)),
              suffixIconConstraints:
                  hasText ? BoxConstraints.loose(Size(48, 28)) : null,
              suffixIcon: hasText ? _buildSuffixIcon(context) : null,
            ),
            onChanged: widget.onChanged ??
                (value) => context
                    .read<CommandPaletteBloc>()
                    .add(CommandPaletteEvent.searchChanged(search: value)),
          );
        },
      ),
    );
  }

  void _clearSearch() {
    controller.clear();
    final onChanged = widget.onChanged;
    if (onChanged != null) {
      onChanged('');
    } else {
      context
          .read<CommandPaletteBloc>()
          .add(const CommandPaletteEvent.clearSearch());
    }
    focusNode.requestFocus();
  }
}
