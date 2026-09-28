import 'dart:async';

import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller_builder.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_builder.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../desktop_grid/desktop_grid_text_cell.dart';
import '../desktop_row_detail/desktop_row_detail_text_cell.dart';
import '../mobile_grid/mobile_grid_text_cell.dart';
import '../mobile_row_detail/mobile_row_detail_text_cell.dart';

abstract class IEditableTextCellSkin {
  const IEditableTextCellSkin();

  factory IEditableTextCellSkin.fromStyle(EditableCellStyle style) {
    return switch (style) {
      EditableCellStyle.desktopGrid => DesktopGridTextCellSkin(),
      EditableCellStyle.desktopRowDetail => DesktopRowDetailTextCellSkin(),
      EditableCellStyle.mobileGrid => MobileGridTextCellSkin(),
      EditableCellStyle.mobileRowDetail => MobileRowDetailTextCellSkin(),
    };
  }

  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    ValueNotifier<bool> compactModeNotifier,
    TextCellBloc bloc,
    FocusNode focusNode,
    TextEditingController textEditingController,
  );
}

class EditableTextCell extends EditableCellWidget {
  EditableTextCell({
    super.key,
    required this.databaseController,
    required this.cellContext,
    required this.skin,
    this.cellController,
  });

  final DatabaseController databaseController;
  final CellContext cellContext;
  final IEditableTextCellSkin skin;

  /// Optional native I/O boundary, like TextCardCell. The real bloc, skin,
  /// focus and text controller remain owned by this cell.
  final TextCellController? cellController;

  @override
  GridEditableTextCell<EditableTextCell> createState() => _TextCellState();
}

class _TextCellState extends GridEditableTextCell<EditableTextCell>
    with AutomaticKeepAliveClientMixin<EditableTextCell> {
  late final TextEditingController _textEditingController;
  bool _hasController = false;
  late final cellBloc = TextCellBloc(
    cellController: widget.cellController ??
        makeCellController(
          widget.databaseController,
          widget.cellContext,
        ).as(),
  );

  // Find can move a lazy row offscreen without focusing it. Preserve an
  // unacknowledged draft, composing range or selection until the cell itself
  // finishes that edit; navigation must not dispose and recreate the editor.
  @override
  bool get wantKeepAlive =>
      _hasController &&
      (_textEditingController.text != (cellBloc.state.content ?? '') ||
          !_textEditingController.selection.isCollapsed ||
          !_textEditingController.value.composing.isCollapsed);

  @override
  void initState() {
    super.initState();
    _textEditingController =
        TextEditingController(text: cellBloc.state.content);
    _hasController = true;
    _textEditingController.addListener(updateKeepAlive);
    updateKeepAlive();
  }

  @override
  void dispose() {
    _textEditingController.removeListener(updateKeepAlive);
    _textEditingController.dispose();
    cellBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocProvider.value(
      value: cellBloc,
      child: BlocListener<TextCellBloc, TextCellState>(
        listenWhen: (previous, current) => previous.content != current.content,
        listener: (context, state) {
          // It's essential to set the new content to the textEditingController.
          // If you don't, the old value in textEditingController will persist and
          // overwrite the correct value, leading to inconsistencies between the
          // displayed text and the actual data.
          _textEditingController.text = state.content ?? "";
        },
        child: Builder(
          builder: (context) {
            return widget.skin.build(
              context,
              widget.cellContainerNotifier,
              widget.databaseController.compactModeNotifier,
              cellBloc,
              focusNode,
              _textEditingController,
            );
          },
        ),
      ),
    );
  }

  @override
  SingleListenerFocusNode focusNode = SingleListenerFocusNode();

  @override
  void onRequestFocus() {
    focusNode.requestFocus();
  }

  @override
  String? onCopy() => cellBloc.state.content;

  @override
  Future<void> focusChanged() {
    if (mounted &&
        !cellBloc.isClosed &&
        cellBloc.state.content != _textEditingController.text.trim()) {
      cellBloc
          .add(TextCellEvent.updateText(_textEditingController.text.trim()));
    }
    return super.focusChanged();
  }
}
