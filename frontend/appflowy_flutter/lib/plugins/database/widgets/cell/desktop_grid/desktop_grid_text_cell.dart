import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/location_cell_suggestions.dart';
import 'package:appflowy/plugins/database/widgets/cell/encrypted_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../editable_cell_skeleton/text.dart';

abstract final class DesktopGridTextCellStyle {
  static const primaryFontSize = 16.0;
  static const primaryFontWeight = FontWeight.w600;

  static TextStyle resolve(
    BuildContext context, {
    required bool isPrimary,
  }) {
    final style = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    if (!isPrimary) {
      return style;
    }

    return style.copyWith(
      color: AFThemeExtension.of(context).strongText,
      fontSize: primaryFontSize,
      fontWeight: primaryFontWeight,
      fontVariations: flowyFontVariationsForWeight(primaryFontWeight),
    );
  }
}

class DesktopGridTextCellSkin extends IEditableTextCellSkin {
  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    ValueNotifier<bool> compactModeNotifier,
    TextCellBloc bloc,
    FocusNode focusNode,
    TextEditingController textEditingController,
  ) {
    return ValueListenableBuilder(
      valueListenable: compactModeNotifier,
      builder: (context, compactMode, data) {
        final padding = compactMode
            ? GridSize.compactCellContentInsets
            : GridSize.cellContentInsets;
        return EncryptedCellGuard(
          viewId: bloc.cellController.viewId,
          fieldId: bloc.cellController.fieldId,
          controller: textEditingController,
          padding: padding,
          child: PropertyStyledTextCell(
            viewId: bloc.cellController.viewId,
            fieldId: bloc.cellController.fieldId,
            rowId: bloc.cellController.rowId,
            controller: textEditingController,
            bloc: bloc,
            childBuilder: (context, align) => Padding(
              padding: padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _IconOrEmoji(),
                  Expanded(
                    child: LocationCellSuggestions(
                      viewId: bloc.cellController.viewId,
                      fieldId: bloc.cellController.fieldId,
                      controller: textEditingController,
                      focusNode: focusNode,
                      child: TextField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        textAlign: align,
                        maxLines:
                            context.watch<TextCellBloc>().state.wrap ? null : 1,
                        style: DesktopGridTextCellStyle.resolve(
                          context,
                          isPrimary: context
                              .read<TextCellBloc>()
                              .cellController
                              .fieldInfo
                              .isPrimary,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IconOrEmoji extends StatelessWidget {
  const _IconOrEmoji();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextCellBloc, TextCellState>(
      builder: (context, state) {
        // if not a title cell, return empty widget
        if (state.emoji == null || state.hasDocument == null) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<String>(
          valueListenable: state.emoji!,
          builder: (context, emoji, _) {
            return emoji.isNotEmpty
                ? Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6.0),
                    child: FlowyText.emoji(
                      optimizeEmojiAlign: true,
                      emoji,
                    ),
                  )
                : ValueListenableBuilder<bool>(
                    valueListenable: state.hasDocument!,
                    builder: (context, hasDocument, _) {
                      return hasDocument
                          ? Padding(
                              padding:
                                  const EdgeInsetsDirectional.only(end: 6.0)
                                      .add(const EdgeInsets.all(1)),
                              child: FlowySvg(
                                FlowySvgs.notes_s,
                                color: Theme.of(context).hintColor,
                              ),
                            )
                          : const SizedBox.shrink();
                    },
                  );
          },
        );
      },
    );
  }
}
