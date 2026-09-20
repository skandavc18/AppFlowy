import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../editable_cell_skeleton/text.dart';

class MobileGridTextCellSkin extends IEditableTextCellSkin {
  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    ValueNotifier<bool> compactModeNotifier,
    TextCellBloc bloc,
    FocusNode focusNode,
    TextEditingController textEditingController,
  ) {
    return Row(
      children: [
        const HSpace(10),
        BlocBuilder<TextCellBloc, TextCellState>(
          buildWhen: (p, c) => p.emoji != c.emoji,
          builder: (context, state) {
            final notifier = state.emoji;
            if (notifier == null) return const SizedBox.shrink();
            return ValueListenableBuilder<String>(
              valueListenable: notifier,
              builder: (context, value, _) {
                final icon = EmojiIconData.fromStorageString(value);
                return icon.isEmpty
                    ? const SizedBox.shrink()
                    : Center(
                        child: RawEmojiIconWidget(emoji: icon, emojiSize: 15),
                      );
              },
            );
          },
        ),
        Expanded(
          child: TextField(
            controller: textEditingController,
            focusNode: focusNode,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                ),
            decoration: const InputDecoration(
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 4),
              isCollapsed: true,
            ),
            onTapOutside: (event) => focusNode.unfocus(),
          ),
        ),
      ],
    );
  }
}
