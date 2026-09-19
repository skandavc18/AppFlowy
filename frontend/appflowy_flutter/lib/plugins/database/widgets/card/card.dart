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
import 'package:appflowy/shared/table_views/table_view_style.dart';
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
import '../cell/card_cell_skeleton/text_card_cell.dart';
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
                return RowCardContent(
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

/// The live card body, with its title editor retained across preview layouts.
class RowCardContent extends StatefulWidget {
  const RowCardContent({
    super.key,
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
  State<RowCardContent> createState() => _RowCardContentState();
}

class _RowCardContentState extends State<RowCardContent> {
  // The editor moves between the card body and the cover's foot. Keep its
  // controller, focus and unsaved title when the preview choice changes.
  final _titleKey = GlobalKey(debugLabel: 'row-card-title-editor');

  @override
  Widget build(BuildContext context) {
    final fields = context.read<CardBloc>().fieldController;
    final isEditing = context.select((CardBloc bloc) => bloc.state.isEditing);
    final title = widget.cells.firstWhereOrNull(
      (cell) => fields.getField(cell.fieldId)?.isPrimary ?? false,
    );
    final style = widget.styleConfiguration;
    final showProperties = style.showProperties || style.preview.showsRowData;
    final child = RowCardPreviewLayout(
      rowMeta: widget.rowMeta,
      mode: style.preview,
      padding: style.cardPadding,
      radius: style.coverRadius,
      tint: style.previewTint,
      userProfile: widget.userProfile,
      isCompact: widget.isCompact,
      isEditing: isEditing,
      showProperties: showProperties,
      titleBuilder: (context, foreground) => title == null
          ? const SizedBox.shrink()
          : _CardContentCell(
              key: _titleKey,
              cellBuilder: widget.cellBuilder,
              cellMeta: title,
              rowMeta: widget.rowMeta,
              isTitle: true,
              styleMap:
                  cardPreviewTitleStyleMap(style.cellStyleMap, foreground),
            ),
      properties: [
        if (showProperties)
          for (final cell in widget.cells)
            if (cell != title)
              _CardContentCell(
                key: ValueKey((cell.rowId, cell.fieldId)),
                cellBuilder: widget.cellBuilder,
                cellMeta: cell,
                rowMeta: widget.rowMeta,
                isTitle: false,
                styleMap: style.cellStyleMap,
              ),
      ],
    );
    return style.hoverStyle == null
        ? child
        : FlowyHover(
            style: style.hoverStyle,
            buildWhenOnHover: () => !context.read<CardBloc>().state.isEditing,
            child: child,
          );
  }
}

/// Focused preview faces, with row fields only when explicitly requested.
/// No row, field, cover or page content is rewritten when the face changes.
class RowCardPreviewLayout extends StatelessWidget {
  const RowCardPreviewLayout({
    super.key,
    required this.rowMeta,
    required this.mode,
    required this.titleBuilder,
    required this.properties,
    this.showProperties = false,
    this.isEditing = false,
    this.userProfile,
    this.isCompact = false,
    this.padding = const EdgeInsets.all(4),
    this.radius = 4,
    this.tint,
  });

  final RowMetaPB rowMeta;
  final CardPreviewMode mode;
  final Widget Function(BuildContext context, Color? foreground) titleBuilder;
  final List<Widget> properties;

  /// Non-board hosts (such as Calendar) may retain their existing properties.
  final bool showProperties;

  /// A page-only card reveals its retained title editor only when requested.
  final bool isEditing;
  final UserProfilePB? userProfile;
  final bool isCompact;
  final EdgeInsets padding;
  final double radius;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (mode == CardPreviewMode.portrait) {
      return _portrait(context);
    }
    final pageAndTitle = mode == CardPreviewMode.pageAndTitle;
    final pageOnly = mode == CardPreviewMode.pageContent;
    final hideTitle = pageOnly && !isEditing;
    final includeProperties = showProperties || mode.showsRowData;
    return ClipRRect(
      key: ValueKey('row-card-face-${mode.id}'),
      borderRadius: BorderRadius.circular(radius),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pageAndTitle || pageOnly)
            CardPagePreview(
              documentId: rowMeta.documentId,
              radius: radius,
              isCompact: isCompact,
              tint: tint,
              height: isCompact ? 144 : 196,
            )
          else if (mode == CardPreviewMode.cover)
            CardCover(
              cover: rowMeta.hasCover() ? rowMeta.cover : null,
              userProfile: userProfile,
              isCompact: isCompact,
              radius: radius,
            ),
          // Keep the editor mounted, but never focusable, painted, hit-tested
          // or announced while this face promises to show only the page.
          Offstage(
            key: const ValueKey('row-card-title-footer'),
            offstage: hideTitle,
            child: TickerMode(
              enabled: !hideTitle,
              child: ExcludeFocus(
                excluding: hideTitle,
                child: Padding(
                  padding: padding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleBuilder(context, null),
                      if (includeProperties && !pageAndTitle && !pageOnly) ...[
                        if (mode.showsRowData && properties.isNotEmpty)
                          const SizedBox(height: 6),
                        ...properties,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _portrait(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final cover = rowMeta.hasCover() ? rowMeta.cover : null;
    final hasCover = CardCover.canRender(cover, userProfile);
    final foreground = hasCover ? Colors.white : null;
    final theme = Theme.of(context);
    return ClipRRect(
      key: const ValueKey('row-card-face-portrait'),
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: tint ?? palette.sunken,
              child: hasCover
                  ? CardCover(
                      cover: cover,
                      userProfile: userProfile,
                      radius: radius,
                      height: double.infinity,
                    )
                  : null,
            ),
          ),
          // A long or enlarged title grows the card, rather than clipping an
          // editor against a fixed portrait height.
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: isCompact ? 164 : 220),
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              heightFactor: 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasCover)
                    const SizedBox(
                      height: 28,
                      child: DecoratedBox(
                        key: ValueKey('row-card-cover-scrim'),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0xCC000000)],
                          ),
                        ),
                      ),
                    ),
                  ColoredBox(
                    // Keep every line over the dark foot, not the transparent
                    // end of a fixed gradient when the title grows.
                    color:
                        hasCover ? const Color(0xCC000000) : Colors.transparent,
                    child: Padding(
                      padding: padding,
                      child: Theme(
                        data: hasCover
                            ? theme.copyWith(
                                hintColor: Colors.white.withValues(alpha: 0.8),
                                textSelectionTheme:
                                    theme.textSelectionTheme.copyWith(
                                  cursorColor: Colors.white,
                                  selectionColor:
                                      Colors.white.withValues(alpha: 0.3),
                                ),
                              )
                            : theme,
                        child: Builder(
                          builder: (context) =>
                              titleBuilder(context, foreground),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Only the title changes ink over a full cover; property styles stay intact.
CardCellStyleMap cardPreviewTitleStyleMap(
  CardCellStyleMap styles,
  Color? foreground,
) {
  final text = styles[FieldType.RichText];
  if (foreground == null || text is! TextCardCellStyle) return styles;
  return {
    ...styles,
    FieldType.RichText: TextCardCellStyle(
      padding: text.padding,
      textStyle: text.textStyle,
      titleTextStyle: text.titleTextStyle.copyWith(color: foreground),
      maxLines: text.maxLines,
    ),
  };
}

class _CardContentCell extends StatefulWidget {
  const _CardContentCell({
    super.key,
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
    cellNotifier = widget.isTitle
        ? EditableCardNotifier(
            isEditing: context.read<CardBloc>().state.isEditing,
          )
        : null;
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
    this.height,
  });

  final RowCoverPB? cover;
  final UserProfilePB? userProfile;
  final bool isCompact;
  final double radius;

  /// A full-cover layout supplies infinity inside a bounded Stack.
  final double? height;

  static bool canRender(RowCoverPB? cover, UserProfilePB? userProfile) =>
      cover != null &&
      cover.data.isNotEmpty &&
      (cover.coverType != CoverTypePB.FileCover ||
          cover.uploadType != FileUploadTypePB.CloudFile ||
          userProfile != null);

  @override
  Widget build(BuildContext context) {
    if (!canRender(cover, userProfile)) {
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
    final height = this.height ?? (isCompact ? 50.0 : 100.0);

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
    this.height,
  });

  final String documentId;
  final bool isCompact;
  final double radius;

  /// The band the writing is set on. Defaults to a neutral wash.
  final Color? tint;

  /// Page cards reserve this viewport even for an empty page.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final preview = RowPagePreview(
      documentId: documentId,
      height: height ?? (isCompact ? 86 : 132),
      scale: isCompact ? 0.52 : 0.58,
      emptyBuilder: (context) => Text(
        LocaleKeys.cardPreview_pageEmpty.tr(),
        style: TextStyle(fontSize: 12, color: palette.textMuted),
      ),
      textBuilder: (context, text) => Text(
        text ?? '',
        maxLines: height == null ? (isCompact ? 4 : 7) : null,
        overflow: TextOverflow.fade,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.5,
          color: palette.textSecondary,
        ),
      ),
    );

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(minHeight: isCompact ? 54 : 84),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, isCompact ? 9 : 12, 12, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
        color: tint ?? palette.sunken,
      ),
      child: height == null
          ? preview
          : SizedBox(height: height, child: ClipRect(child: preview)),
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
    this.showProperties = true,
    this.cardPadding = const EdgeInsets.all(4),
    this.coverRadius = 4,
    this.preview = CardPreviewMode.cover,
    this.previewTint,
    this.hoverStyle,
  });

  final CardCellStyleMap cellStyleMap;
  final bool showAccessory;

  /// Boards opt out of row fields; other card hosts retain their existing UI.
  final bool showProperties;
  final EdgeInsets cardPadding;
  final double coverRadius;

  /// What the card shows above its title.
  final CardPreviewMode preview;

  /// The band a page preview is set on, when the host has a colour to lend.
  final Color? previewTint;

  final HoverStyle? hoverStyle;
}
