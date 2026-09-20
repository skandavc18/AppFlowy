import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller_builder.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../editable_cell_builder.dart';
import 'card_cell.dart';

class TextCardCellStyle extends CardCellStyle {
  TextCardCellStyle({
    required super.padding,
    required this.textStyle,
    required this.titleTextStyle,
    this.maxLines = 1,
  });

  final TextStyle textStyle;
  final TextStyle titleTextStyle;
  final int? maxLines;
}

class TextCardCell extends CardCell<TextCardCellStyle> with EditableCell {
  const TextCardCell({
    super.key,
    required super.style,
    required this.databaseController,
    required this.cellContext,
    this.cellController,
    this.showNotes = false,
    this.editableNotifier,
  });

  final DatabaseController databaseController;
  final CellContext cellContext;
  final bool showNotes;

  /// Optional cell-data boundary; the cell bloc owns and disposes it.
  /// By default the controller is created from the database's row cache.
  final TextCellController? cellController;

  @override
  final EditableCardNotifier? editableNotifier;

  @override
  State<TextCardCell> createState() => _TextCellState();
}

class _TextCellState extends State<TextCardCell> {
  late final cellBloc = TextCellBloc(
    cellController: widget.cellController ??
        makeCellController(
          widget.databaseController,
          widget.cellContext,
        ).as(),
  );
  late final TextEditingController _textEditingController;
  final focusNode = SingleListenerFocusNode();

  @override
  void initState() {
    super.initState();
    _textEditingController =
        TextEditingController(text: cellBloc.state.content);

    if (widget.editableNotifier?.isCellEditing.value ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusNode.requestFocus();
        cellBloc.add(const TextCellEvent.enableEdit(true));
      });
    }

    // If the focusNode lost its focus, the widget's editableNotifier will
    // set to false, which will cause the [EditableRowNotifier] to receive
    // end edit event.
    focusNode.addListener(_onFocusChanged);
    _bindEditableNotifier();
  }

  void _onFocusChanged() {
    if (!focusNode.hasFocus) {
      widget.editableNotifier?.isCellEditing.value = false;
      cellBloc.add(const TextCellEvent.enableEdit(false));
      cellBloc.add(TextCellEvent.updateText(_textEditingController.text));
    }
  }

  void _bindEditableNotifier() {
    widget.editableNotifier?.isCellEditing.addListener(() {
      if (!mounted) {
        return;
      }

      final isEditing = widget.editableNotifier?.isCellEditing.value ?? false;
      if (isEditing) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => focusNode.requestFocus());
      }
      cellBloc.add(TextCellEvent.enableEdit(isEditing));
    });
  }

  @override
  void didUpdateWidget(covariant oldWidget) {
    if (oldWidget.editableNotifier != widget.editableNotifier) {
      _bindEditableNotifier();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final isTitle = cellBloc.cellController.fieldInfo.isPrimary;
    return BlocProvider.value(
      value: cellBloc,
      child: BlocListener<TextCellBloc, TextCellState>(
        listenWhen: (previous, current) => previous.content != current.content,
        listener: (context, state) {
          _textEditingController.text = state.content ?? "";
        },
        child: isTitle ? _buildTitle() : _buildText(),
      ),
    );
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    widget.editableNotifier?.isCellEditing
        .removeListener(_bindEditableNotifier);
    focusNode.dispose();
    cellBloc.close();
    super.dispose();
  }

  Widget? _buildIcon(String? value) {
    final icon = EmojiIconData.fromStorageString(value);
    if (icon.isNotEmpty) {
      return RawEmojiIconWidget(
        emoji: icon,
        emojiSize: Theme.of(context).textTheme.bodyMedium?.fontSize ?? 16,
      );
    }

    if (widget.showNotes) {
      return FlowyTooltip(
        message: LocaleKeys.board_notesTooltip.tr(),
        child: Padding(
          padding: const EdgeInsets.all(1.0),
          child: FlowySvg(
            FlowySvgs.notes_s,
            color: Theme.of(context).hintColor,
          ),
        ),
      );
    }
    return null;
  }

  Widget _buildText() {
    return PropertyStyledTextCell(
      viewId: cellBloc.cellController.viewId,
      fieldId: cellBloc.cellController.fieldId,
      rowId: cellBloc.cellController.rowId,
      controller: _textEditingController,
      bloc: cellBloc,
      childBuilder: (context, align) =>
          BlocBuilder<TextCellBloc, TextCellState>(
        builder: (context, state) {
          final content = state.content ?? "";

          return content.isEmpty
              ? const SizedBox.shrink()
              : Container(
                  padding: widget.style.padding,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    content,
                    style: widget.style.textStyle,
                    maxLines: widget.style.maxLines,
                    textAlign: align,
                  ),
                );
        },
      ),
    );
  }

  Widget _buildTitle() {
    final textField = _buildTextField();
    return BlocBuilder<TextCellBloc, TextCellState>(
      builder: (context, state) {
        final resolved =
            widget.style.padding.resolve(Directionality.of(context));
        final padding = EdgeInsetsDirectional.only(
          start: resolved.left,
          top: resolved.top,
          bottom: resolved.bottom,
        );
        Widget buildIcon(String? value) {
          final icon = _buildIcon(value);
          return icon == null
              ? const SizedBox.shrink()
              : Padding(padding: padding, child: icon);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            state.emoji == null
                ? buildIcon(null)
                : ValueListenableBuilder<String>(
                    valueListenable: state.emoji!,
                    builder: (context, value, _) => buildIcon(value),
                  ),
            // Keep the editor at the same depth when the row icon changes.
            Expanded(child: textField),
          ],
        );
      },
    );
  }

  Widget _buildTextField() {
    return BlocSelector<TextCellBloc, TextCellState, bool>(
      selector: (state) => state.enableEdit,
      builder: (context, isEditing) {
        return IgnorePointer(
          ignoring: !isEditing,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  focusNode.unfocus(),
              const SimpleActivator(LogicalKeyboardKey.enter): () =>
                  focusNode.unfocus(),
            },
            child: TextField(
              controller: _textEditingController,
              focusNode: focusNode,
              onEditingComplete: () => focusNode.unfocus(),
              onSubmitted: (_) => focusNode.unfocus(),
              maxLines: null,
              minLines: 1,
              textInputAction: TextInputAction.done,
              readOnly: !isEditing,
              enableInteractiveSelection: isEditing,
              style: widget.style.titleTextStyle,
              decoration: InputDecoration(
                contentPadding: widget.style.padding,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                isDense: true,
                isCollapsed: true,
                hintText: LocaleKeys.grid_row_titlePlaceholder.tr(),
                hintStyle: widget.style.titleTextStyle.copyWith(
                  color: Theme.of(context).hintColor,
                ),
              ),
              onTapOutside: (_) {},
            ),
          ),
        );
      },
    );
  }
}

class SimpleActivator with Diagnosticable implements ShortcutActivator {
  const SimpleActivator(
    this.trigger, {
    this.includeRepeats = true,
  });

  final LogicalKeyboardKey trigger;
  final bool includeRepeats;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    return (event is KeyDownEvent ||
            (includeRepeats && event is KeyRepeatEvent)) &&
        trigger == event.logicalKey;
  }

  @override
  String debugDescribeKeys() =>
      kDebugMode ? trigger.debugName ?? trigger.toStringShort() : '';

  @override
  Iterable<LogicalKeyboardKey>? get triggers => <LogicalKeyboardKey>[trigger];
}
