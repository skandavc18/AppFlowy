import 'package:appflowy/plugins/document/presentation/editor_plugins/menu/menu_extension.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Geometry shared by the menus that ask what a paste should become.
abstract final class PasteChoiceMenuMetrics {
  static const double width = 288;
  static const double padding = 6;
  static const double headerHeight = 32;
  static const double rowHeight = 36;

  static double heightFor(int choices) =>
      padding * 2 + headerHeight + rowHeight * choices;
}

/// One answer a paste menu offers.
@immutable
class PasteChoice<T> {
  const PasteChoice({
    required this.value,
    required this.label,
    this.trailing,
  });

  final T value;
  final String label;

  /// A quiet detail at the row's end, like the site an embed comes from.
  final Widget? trailing;
}

/// Holds a paste menu at the caret, over the editor, until it is answered,
/// dismissed or the caret moves.
class PasteChoiceMenuOverlay {
  PasteChoiceMenuOverlay({
    required this.context,
    required this.editorState,
  });

  final BuildContext context;
  final EditorState editorState;
  OverlayEntry? _entry;

  bool get isShowing => _entry != null;

  /// Shows the menu after this frame, once the pasted text is laid out and
  /// the caret can be measured. [builder] receives the callback that takes the
  /// menu down again.
  void show({
    required int choices,
    required Widget Function(VoidCallback dismiss) builder,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _show(choices: choices, builder: builder);
    });
  }

  void dismiss() {
    if (_entry != null) {
      keepEditorFocusNotifier.decrease();
    }
    _entry?.remove();
    _entry = null;
  }

  void _show({
    required int choices,
    required Widget Function(VoidCallback dismiss) builder,
  }) {
    if (_entry != null || !context.mounted || editorState.isDisposed) {
      return;
    }
    final Size editorSize = editorState.renderBox?.size ?? Size.zero;
    if (editorSize == Size.zero) return;
    final menuPosition = editorState.calculateMenuOffset(
      menuWidth: PasteChoiceMenuMetrics.width,
      menuHeight: PasteChoiceMenuMetrics.heightFor(choices),
    );
    if (menuPosition == null) return;
    final ltrb = menuPosition.ltrb;

    _entry = OverlayEntry(
      builder: (context) => SizedBox(
        height: editorSize.height,
        width: editorSize.width,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: dismiss,
          child: Stack(
            children: [
              ltrb.buildPositioned(child: builder(dismiss)),
            ],
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_entry!);
    keepEditorFocusNotifier.increase();
  }
}

/// A short question with its answers, answered by click or by keyboard:
/// arrows move, Enter chooses, Escape keeps the paste as it is.
class PasteChoiceMenu<T> extends StatefulWidget {
  const PasteChoiceMenu({
    super.key,
    required this.editorState,
    required this.title,
    required this.choices,
    required this.onSelect,
    required this.onDismiss,
    this.leading,
    this.initialIndex = 0,
  });

  final EditorState editorState;
  final String title;

  /// Drawn before the title, like the mark of the site a link belongs to.
  final Widget? leading;
  final List<PasteChoice<T>> choices;
  final int initialIndex;
  final ValueChanged<T> onSelect;
  final VoidCallback onDismiss;

  @override
  State<PasteChoiceMenu<T>> createState() => _PasteChoiceMenuState<T>();
}

class _PasteChoiceMenuState<T> extends State<PasteChoiceMenu<T>> {
  final focusNode = FocusNode(debugLabel: 'paste_choice_menu');
  late final ValueNotifier<int> selectedIndex = ValueNotifier(
    widget.initialIndex.clamp(0, widget.choices.length - 1),
  );

  EditorState get editorState => widget.editorState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => focusNode.requestFocus(),
    );
    editorState.selectionNotifier.addListener(dismiss);
  }

  @override
  void dispose() {
    focusNode.dispose();
    selectedIndex.dispose();
    editorState.selectionNotifier.removeListener(dismiss);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    // Paper keeps its warm stationery instead of the cool popup surface.
    final background = PaperTheme.isEnabled(context)
        ? PaperTheme.popupBackground
        : theme.surfaceColorScheme.primary;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      child: Container(
        width: PasteChoiceMenuMetrics.width,
        height: PasteChoiceMenuMetrics.heightFor(widget.choices.length),
        padding: const EdgeInsets.all(PasteChoiceMenuMetrics.padding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: background,
          boxShadow: theme.shadow.medium,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: PasteChoiceMenuMetrics.headerHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    if (widget.leading != null) ...[
                      widget.leading!,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: FlowyText.semibold(
                        widget.title,
                        color: theme.textColorScheme.primary,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (var i = 0; i < widget.choices.length; i++) buildItem(i),
          ],
        ),
      ),
    );
  }

  Widget buildItem(int index) {
    final choice = widget.choices[index];
    return ValueListenableBuilder(
      valueListenable: selectedIndex,
      builder: (context, value, child) => SizedBox(
        height: PasteChoiceMenuMetrics.rowHeight,
        child: FlowyButton(
          isSelected: index == value,
          text: FlowyText(choice.label),
          rightIcon: choice.trailing,
          onTap: () => widget.onSelect(choice.value),
        ),
      ),
    );
  }

  KeyEventResult onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final length = widget.choices.length;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      widget.onSelect(widget.choices[selectedIndex.value].value);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      dismiss();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.backspace) {
      // Editing goes on: the key still reaches the page.
      dismiss();
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      selectedIndex.value = (selectedIndex.value - 1 + length) % length;
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      selectedIndex.value = (selectedIndex.value + 1) % length;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void dismiss() => widget.onDismiss();
}
