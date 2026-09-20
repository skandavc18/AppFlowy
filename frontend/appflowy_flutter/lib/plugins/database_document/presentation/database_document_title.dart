import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_builder.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_skeleton/text.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/emoji_picker_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'database_document_title_bloc.dart';

// This widget is largely copied from `workspace/presentation/widgets/view_title_bar.dart` intentionally instead of opting for an abstraction. We can make an abstraction after the view refactor is done and there's more clarity in that department.

// workspaces / ... / database view name / row name
class ViewTitleBarWithRow extends StatelessWidget {
  const ViewTitleBarWithRow({
    super.key,
    required this.view,
    required this.databaseId,
    required this.rowId,
  });

  final ViewPB view;
  final String databaseId;
  final String rowId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DatabaseDocumentTitleBloc(
        view: view,
        rowId: rowId,
      ),
      child: BlocBuilder<DatabaseDocumentTitleBloc, DatabaseDocumentTitleState>(
        builder: (context, state) {
          if (state.ancestors.isEmpty) {
            return const SizedBox.shrink();
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              height: 24,
              child: Row(
                // refresh the view title bar when the ancestors changed
                key: ValueKey(state.ancestors.hashCode),
                children: _buildViewTitles(state.ancestors),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildViewTitles(List<ViewPB> views) {
    // if the level is too deep, only show the root view, the database view and the row
    return views.length > 2
        ? [
            _buildViewButton(views[1]),
            const FlowySvg(FlowySvgs.title_bar_divider_s),
            const FlowyText.regular(' ... '),
            const FlowySvg(FlowySvgs.title_bar_divider_s),
            _buildViewButton(views.last),
            const FlowySvg(FlowySvgs.title_bar_divider_s),
            _buildRowName(),
          ]
        : [
            ...views
                .map(
                  (e) => [
                    _buildViewButton(e),
                    const FlowySvg(FlowySvgs.title_bar_divider_s),
                  ],
                )
                .flattened,
            _buildRowName(),
          ];
  }

  Widget _buildViewButton(ViewPB view) {
    return FlowyTooltip(
      message: view.name,
      child: ViewTitle(
        view: view,
        behavior: ViewTitleBehavior.uneditable,
        onUpdated: () {},
      ),
    );
  }

  Widget _buildRowName() {
    return _RowName(
      rowId: rowId,
    );
  }
}

class _RowName extends StatelessWidget {
  const _RowName({
    required this.rowId,
  });

  final String rowId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DatabaseDocumentTitleBloc, DatabaseDocumentTitleState>(
      builder: (context, state) {
        if (state.databaseController == null) {
          return const SizedBox.shrink();
        }

        final cellBuilder = EditableCellBuilder(
          databaseController: state.databaseController!,
        );

        return cellBuilder.buildCustom(
          CellContext(
            fieldId: state.fieldId!,
            rowId: rowId,
          ),
          skinMap: EditableCellSkinMap(textSkin: _TitleSkin()),
        );
      },
    );
  }
}

class _TitleSkin extends IEditableTextCellSkin {
  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    ValueNotifier<bool> compactModeNotifier,
    TextCellBloc bloc,
    FocusNode focusNode,
    TextEditingController textEditingController,
  ) {
    return BlocSelector<TextCellBloc, TextCellState, String>(
      selector: (state) => state.content ?? "",
      builder: (context, content) {
        final name = content.isEmpty
            ? LocaleKeys.grid_row_titlePlaceholder.tr()
            : content;
        return BlocBuilder<DatabaseDocumentTitleBloc,
            DatabaseDocumentTitleState>(
          builder: (context, state) {
            final access = context.watch<PageAccessLevelBloc?>()?.state;
            final editable = access == null
                ? !(state.databaseController?.view.isLocked ?? false)
                : !access.isLoadingLockStatus && access.isEditable;
            final documentId = state.rowController?.rowMeta.documentId;
            return FlowyTooltip(
              message: name,
              child: AppFlowyPopover(
                triggerActions: editable
                    ? PopoverTriggerFlags.click
                    : PopoverTriggerFlags.none,
                constraints: const BoxConstraints(
                  maxWidth: 300,
                  maxHeight: 44,
                ),
                direction: PopoverDirection.bottomWithLeftAligned,
                offset: const Offset(0, 18),
                popupBuilder: (_) {
                  return RenameRowPopover(
                    textController: textEditingController,
                    icon: state.icon ?? EmojiIconData.none(),
                    documentId: documentId == null || documentId.isEmpty
                        ? bloc.cellController.rowId
                        : documentId,
                    editable: editable,
                    onUpdateIcon: (icon) {
                      final access =
                          context.read<PageAccessLevelBloc?>()?.state;
                      if (!editable ||
                          (access != null &&
                              (access.isLoadingLockStatus ||
                                  !access.isEditable))) {
                        return;
                      }
                      context
                          .read<DatabaseDocumentTitleBloc>()
                          .add(DatabaseDocumentTitleEvent.updateIcon(icon));
                    },
                    onUpdateName: (text) =>
                        bloc.add(TextCellEvent.updateText(text)),
                  );
                },
                child: FlowyButton(
                  useIntrinsicWidth: true,
                  onTap: editable ? () {} : null,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  text: Row(
                    children: [
                      if (state.icon?.isNotEmpty ?? false) ...[
                        RawEmojiIconWidget(emoji: state.icon!, emojiSize: 14),
                        const HSpace(4.0),
                      ],
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: FlowyText.regular(
                          name,
                          overflow: TextOverflow.ellipsis,
                          fontSize: 14.0,
                          figmaLineHeight: 18.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class RenameRowPopover extends StatefulWidget {
  const RenameRowPopover({
    super.key,
    required this.textController,
    required this.onUpdateName,
    required this.onUpdateIcon,
    required this.icon,
    this.tabs = kAllIconPickerTabs,
    this.documentId,
    this.editable = true,
  });

  final TextEditingController textController;
  final EmojiIconData icon;
  final String? documentId;
  final bool editable;

  final ValueChanged<String> onUpdateName;
  final ValueChanged<EmojiIconData> onUpdateIcon;
  final List<PickerTabType> tabs;

  @override
  State<RenameRowPopover> createState() => _RenameRowPopoverState();
}

class _RenameRowPopoverState extends State<RenameRowPopover> {
  @override
  void initState() {
    super.initState();
    if (widget.editable) {
      widget.textController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.textController.value.text.characters.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.editable)
          EmojiPickerButton(
            emoji: widget.icon,
            documentId: widget.documentId,
            direction: PopoverDirection.bottomWithCenterAligned,
            offset: const Offset(0, 18),
            defaultIcon: const FlowySvg(FlowySvgs.document_s),
            onSubmitted: (r, _) {
              if (!mounted || !widget.editable) return;
              widget.onUpdateIcon(r.data);
              if (!r.keepOpen) PopoverContainer.of(context).close();
            },
            tabs: widget.tabs,
          )
        else
          SizedBox.square(
            dimension: 30,
            child: Center(
              child: widget.icon.isEmpty
                  ? const FlowySvg(FlowySvgs.document_s)
                  : RawEmojiIconWidget(emoji: widget.icon, emojiSize: 18),
            ),
          ),
        const HSpace(6),
        Flexible(
          child: SizedBox(
            height: 36.0,
            width: 220,
            child: FlowyTextField(
              controller: widget.textController,
              readOnly: !widget.editable,
              autoFocus: widget.editable,
              maxLength: 256,
              onSubmitted: (text) {
                if (!widget.editable) return;
                widget.onUpdateName(text);
                PopoverContainer.of(context).close();
              },
              onCanceled: () {
                if (widget.editable) {
                  widget.onUpdateName(widget.textController.text);
                }
              },
              showCounter: false,
            ),
          ),
        ),
      ],
    );
  }
}
