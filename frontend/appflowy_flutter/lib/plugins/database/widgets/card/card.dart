import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/mobile/presentation/database/card/card.dart';
import 'package:appflowy/plugins/database/application/card_preview.dart';
import 'package:appflowy/plugins/database/application/field/field_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_cache.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/row/action.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/table_views/row_page_preview.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

import '../cell/card_cell_builder.dart';
import '../cell/card_cell_skeleton/card_cell.dart';
import 'card_bloc.dart';
import 'container/accessory.dart';
import 'container/card_container.dart';

/// Edit a database row with card style widget
class RowCard extends StatefulWidget {
  const RowCard({
    super.key,
    required this.fieldController,
    required this.rowMeta,
    required this.viewId,
    required this.isEditing,
    required this.rowCache,
    required this.cellBuilder,
    required this.onTap,
    required this.onStartEditing,
    required this.onEndEditing,
    required this.styleConfiguration,
    this.onShiftTap,
    this.groupingFieldId,
    this.groupId,
    required this.userProfile,
    this.isCompact = false,
  });

  final FieldController fieldController;
  final RowMetaPB rowMeta;
  final String viewId;
  final String? groupingFieldId;
  final String? groupId;

  final bool isEditing;
  final RowCache rowCache;

  /// The [CardCellBuilder] is used to build the card cells.
  final CardCellBuilder cellBuilder;

  /// Called when the user taps on the card.
  final void Function(BuildContext context) onTap;

  final void Function(BuildContext context)? onShiftTap;

  /// Called when the user starts editing the card.
  final VoidCallback onStartEditing;

  /// Called when the user ends editing the card.
  final VoidCallback onEndEditing;

  final RowCardStyleConfiguration styleConfiguration;

  /// Specifically the token is used to handle requests to retrieve images
  /// from cloud storage, such as the card cover.
  final UserProfilePB? userProfile;

  /// Whether the card is in a narrow space.
  /// This is used to determine eg. the Cover height.
  final bool isCompact;

  @override
  State<RowCard> createState() => _RowCardState();
}

class _RowCardState extends State<RowCard> {
  final popoverController = PopoverController();
  late final CardBloc _cardBloc;

  @override
  void initState() {
    super.initState();
    final rowController = RowController(
      viewId: widget.viewId,
      rowMeta: widget.rowMeta,
      rowCache: widget.rowCache,
    );

    _cardBloc = CardBloc(
      fieldController: widget.fieldController,
      viewId: widget.viewId,
      groupFieldId: widget.groupingFieldId,
      isEditing: widget.isEditing,
      rowController: rowController,
    )..add(const CardEvent.initial());
  }

  @override
  void didUpdateWidget(covariant oldWidget) {
    if (widget.isEditing != _cardBloc.state.isEditing) {
      _cardBloc.add(CardEvent.setIsEditing(widget.isEditing));
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _cardBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cardBloc,
      child: BlocListener<CardBloc, CardState>(
        listenWhen: (previous, current) =>
            previous.isEditing != current.isEditing,
        listener: (context, state) {
          if (!state.isEditing) {
            widget.onEndEditing();
          }
        },
        child: UniversalPlatform.isMobile ? _mobile() : _desktop(),
      ),
    );
  }

  Widget _mobile() {
    return BlocBuilder<CardBloc, CardState>(
      builder: (context, state) {
        return GestureDetector(
          onTap: () => widget.onTap(context),
          behavior: HitTestBehavior.opaque,
          child: MobileCardContent(
            userProfile: widget.userProfile,
            rowMeta: state.rowMeta,
            cellBuilder: widget.cellBuilder,
            styleConfiguration: widget.styleConfiguration,
            cells: state.cells,
          ),
        );
      },
    );
  }

  Widget _desktop() {
    final accessories = widget.styleConfiguration.showAccessory
        ? const <CardAccessory>[
            EditCardAccessory(),
            MoreCardOptionsAccessory(),
          ]
        : null;
    return AppFlowyPopover(
      controller: popoverController,
      triggerActions: PopoverTriggerFlags.none,
      constraints: BoxConstraints.loose(const Size(140, 200)),
      direction: PopoverDirection.rightWithCenterAligned,
      popupBuilder: (_) => RowActionMenu.board(
        viewId: _cardBloc.viewId,
        rowId: _cardBloc.rowController.rowId,
        groupId: widget.groupId,
      ),
      child: Builder(
        builder: (context) {
          return RowCardContainer(
            buildAccessoryWhen: () =>
                !context.watch<CardBloc>().state.isEditing,
            accessories: accessories ?? [],
            openAccessory: _handleOpenAccessory,
            onTap: widget.onTap,
            onShiftTap: widget.onShiftTap,
            child: BlocBuilder<CardBloc, CardState>(
              builder: (context, state) {
                return _CardContent(
                  rowMeta: state.rowMeta,
                  cellBuilder: widget.cellBuilder,
                  styleConfiguration: widget.styleConfiguration,
                  cells: state.cells,
                  userProfile: widget.userProfile,
                  isCompact: widget.isCompact,
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _handleOpenAccessory(AccessoryType newAccessoryType) {
    switch (newAccessoryType) {
      case AccessoryType.edit:
        widget.onStartEditing();
        break;
      case AccessoryType.more:
        popoverController.show();
        break;
    }
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.rowMeta,
    required this.cellBuilder,
    required this.cells,
    required this.styleConfiguration,
    this.userProfile,
    this.isCompact = false,
  });

  final RowMetaPB rowMeta;
  final CardCellBuilder cellBuilder;
  final List<CellMeta> cells;
  final RowCardStyleConfiguration styleConfiguration;
  final UserProfilePB? userProfile;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (styleConfiguration.preview == CardPreviewMode.pageContent)
          CardPagePreview(
            documentId: rowMeta.documentId,
            radius: styleConfiguration.coverRadius,
            isCompact: isCompact,
            tint: styleConfiguration.previewTint,
          )
        else if (styleConfiguration.preview == CardPreviewMode.cover)
          CardCover(
            cover: rowMeta.cover,
            userProfile: userProfile,
            isCompact: isCompact,
            radius: styleConfiguration.coverRadius,
          ),
        Padding(
          padding: styleConfiguration.cardPadding,
          child: Column(
            children: _makeCells(context, rowMeta, cells),
          ),
        ),
      ],
    );
    return styleConfiguration.hoverStyle == null
        ? child
        : FlowyHover(
            style: styleConfiguration.hoverStyle,
            buildWhenOnHover: () => !context.read<CardBloc>().state.isEditing,
            child: child,
          );
  }

  List<Widget> _makeCells(
    BuildContext context,
    RowMetaPB rowMeta,
    List<CellMeta> cells,
  ) {
    return cells
        .mapIndexed(
          (int index, CellMeta cellMeta) => _CardContentCell(
            cellBuilder: cellBuilder,
            cellMeta: cellMeta,
            rowMeta: rowMeta,
            isTitle: index == 0,
            styleMap: styleConfiguration.cellStyleMap,
          ),
        )
        .toList();
  }
}

class _CardContentCell extends StatefulWidget {
  const _CardContentCell({
    required this.cellBuilder,
    required this.cellMeta,
    required this.rowMeta,
    required this.isTitle,
    required this.styleMap,
  });

  final CellMeta cellMeta;
  final RowMetaPB rowMeta;
  final CardCellBuilder cellBuilder;
  final CardCellStyleMap styleMap;
  final bool isTitle;

  @override
  State<_CardContentCell> createState() => _CardContentCellState();
}

class _CardContentCellState extends State<_CardContentCell> {
  late final EditableCardNotifier? cellNotifier;

  @override
  void initState() {
    super.initState();
    cellNotifier = widget.isTitle ? EditableCardNotifier() : null;
    cellNotifier?.isCellEditing.addListener(listener);
  }

  void listener() {
    final isEditing = cellNotifier!.isCellEditing.value;
    context.read<CardBloc>().add(CardEvent.setIsEditing(isEditing));
  }

  @override
  void dispose() {
    cellNotifier?.isCellEditing.removeListener(listener);
    cellNotifier?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CardBloc, CardState>(
      listenWhen: (previous, current) =>
          previous.isEditing != current.isEditing,
      listener: (context, state) {
        cellNotifier?.isCellEditing.value = state.isEditing;
      },
      child: widget.cellBuilder.build(
        cellContext: widget.cellMeta.cellContext(),
        styleMap: widget.styleMap,
        cellNotifier: cellNotifier,
        hasNotes: !widget.rowMeta.isDocumentEmpty,
      ),
    );
  }
}

class CardCover extends StatelessWidget {
  const CardCover({
    super.key,
    this.cover,
    this.userProfile,
    this.isCompact = false,
    this.radius = 4,
  });

  final RowCoverPB? cover;
  final UserProfilePB? userProfile;
  final bool isCompact;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (cover == null ||
        cover!.data.isEmpty ||
        cover!.uploadType == FileUploadTypePB.CloudFile &&
            userProfile == null) {
      return const SizedBox.shrink();
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
        color: Theme.of(context).cardColor,
      ),
      child: Row(
        children: [
          Expanded(child: _renderCover(context, cover!)),
        ],
      ),
    );
  }

  Widget _renderCover(BuildContext context, RowCoverPB cover) {
    final height = isCompact ? 50.0 : 100.0;

    if (cover.coverType == CoverTypePB.FileCover) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: AFImage(
          url: cover.data,
          uploadType: cover.uploadType,
          userProfile: userProfile,
        ),
      );
    }

    if (cover.coverType == CoverTypePB.AssetCover) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.asset(
          PageStyleCoverImageType.builtInImagePath(cover.data),
          fit: BoxFit.cover,
        ),
      );
    }

    if (cover.coverType == CoverTypePB.ColorCover) {
      final color = FlowyTint.fromId(cover.data)?.color(context) ??
          cover.data.tryToColor();
      return Container(
        height: height,
        width: double.infinity,
        color: color,
      );
    }

    if (cover.coverType == CoverTypePB.GradientCover) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: FlowyGradientColor.fromId(cover.data).linear,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// The opening of a row's own page, standing where a cover would.
class CardPagePreview extends StatelessWidget {
  const CardPagePreview({
    super.key,
    required this.documentId,
    this.isCompact = false,
    this.radius = 4,
    this.tint,
  });

  final String documentId;
  final bool isCompact;
  final double radius;

  /// The band the writing is set on. Defaults to a neutral wash.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AFThemeExtension.of(context).textColor.withValues(alpha: 0.7);
    final faint = theme.hintColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(minHeight: isCompact ? 54 : 84),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, isCompact ? 9 : 12, 12, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
        color: tint ?? AFThemeExtension.of(context).greyHover,
      ),
      child: RowPagePreview(
        documentId: documentId,
        height: isCompact ? 86 : 132,
        scale: isCompact ? 0.52 : 0.58,
        emptyBuilder: (context) => Text(
          LocaleKeys.cardPreview_pageEmpty.tr(),
          style: TextStyle(fontSize: 12, color: faint),
        ),
        textBuilder: (context, text) => Text(
          text ?? '',
          maxLines: isCompact ? 4 : 7,
          overflow: TextOverflow.fade,
          style: TextStyle(fontSize: 12.5, height: 1.5, color: muted),
        ),
      ),
    );
  }
}

class EditCardAccessory extends StatelessWidget with CardAccessory {
  const EditCardAccessory({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(3.0),
      child: FlowySvg(
        FlowySvgs.edit_s,
        color: Theme.of(context).hintColor,
      ),
    );
  }

  @override
  AccessoryType get type => AccessoryType.edit;
}

class MoreCardOptionsAccessory extends StatelessWidget with CardAccessory {
  const MoreCardOptionsAccessory({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(3.0),
      child: FlowySvg(
        FlowySvgs.three_dots_s,
        color: Theme.of(context).hintColor,
      ),
    );
  }

  @override
  AccessoryType get type => AccessoryType.more;
}

class RowCardStyleConfiguration {
  const RowCardStyleConfiguration({
    required this.cellStyleMap,
    this.showAccessory = true,
    this.cardPadding = const EdgeInsets.all(4),
    this.coverRadius = 4,
    this.preview = CardPreviewMode.cover,
    this.previewTint,
    this.hoverStyle,
  });

  final CardCellStyleMap cellStyleMap;
  final bool showAccessory;
  final EdgeInsets cardPadding;
  final double coverRadius;

  /// What the card shows above its title.
  final CardPreviewMode preview;

  /// The band a page preview is set on, when the host has a colour to lend.
  final Color? previewTint;

  final HoverStyle? hoverStyle;
}
