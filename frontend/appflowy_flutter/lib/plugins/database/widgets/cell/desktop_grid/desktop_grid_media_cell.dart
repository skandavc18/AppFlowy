import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet_media_upload.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/media_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_skeleton/media.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/media_cell_editor.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/mobile_media_cell_editor.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

class GridMediaCellSkin extends IEditableMediaCellSkin {
  const GridMediaCellSkin({this.isMobileRowDetail = false});

  final bool isMobileRowDetail;

  @override
  void dispose() {}

  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    PopoverController popoverController,
    MediaCellBloc bloc,
  ) {
    final isMobile = UniversalPlatform.isMobile;

    Widget child = BlocBuilder<MediaCellBloc, MediaCellState>(
      builder: (context, state) {
        final wrapContent = context.read<MediaCellBloc>().wrapContent;
        final viewId = context.read<MediaCellBloc>().cellController.viewId;
        final fieldId = context.read<MediaCellBloc>().cellController.fieldId;
        final rowId = context.read<MediaCellBloc>().cellController.rowId;

        return ValueListenableBuilder<PropertyStyles>(
          valueListenable: PropertyStyleRegistry.instance.listenable(viewId),
          builder: (context, styles, _) {
            final style = styles.cellStyle(fieldId, rowId);
            final extent =
                (style?.thumbnailSize ?? PropertyThumbnailSize.medium).extent;
            final align = style?.align ?? PropertyAlign.center;

            final List<Widget> children = state.files
                .map<Widget>(
                  (file) => GestureDetector(
                    onTap: () => _openOrExpandFile(context, file, state.files),
                    child: Padding(
                      padding: wrapContent
                          ? const EdgeInsets.only(right: 4)
                          : EdgeInsets.zero,
                      child: _FilePreviewRender(file: file, extent: extent),
                    ),
                  ),
                )
                .toList();

            if (isMobileRowDetail && state.files.isEmpty) {
              children.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    LocaleKeys.grid_row_textPlaceholder.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 16,
                          color: Theme.of(context).hintColor,
                        ),
                  ),
                ),
              );
            }

            if (!isMobile && wrapContent) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    runSpacing: 4,
                    alignment: align.wrapAlignment,
                    children: children,
                  ),
                ),
              );
            }

            // No forced full width: the strip shrink-wraps, so the cell's own
            // alignment is what places it.
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SeparatedRow(
                  separatorBuilder: () => const HSpace(4),
                  children: children,
                ),
              ),
            );
          },
        );
      },
    );

    if (!isMobile) {
      child = AppFlowyPopover(
        controller: popoverController,
        constraints: const BoxConstraints(
          minWidth: 250,
          maxWidth: 250,
          maxHeight: 400,
        ),
        margin: EdgeInsets.zero,
        triggerActions: PopoverTriggerFlags.none,
        direction: PopoverDirection.bottomWithCenterAligned,
        popupBuilder: (_) => BlocProvider.value(
          value: context.read<MediaCellBloc>(),
          child: const MediaCellEditor(),
        ),
        onClose: () => cellContainerNotifier.isFocus = false,
        child: child,
      );
    } else {
      child = Align(
        alignment: AlignmentDirectional.centerStart,
        child: child,
      );

      if (isMobileRowDetail) {
        child = Container(
          decoration: BoxDecoration(
            border: Border.fromBorderSide(
              BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            borderRadius: const BorderRadius.all(Radius.circular(14)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: AlignmentDirectional.centerStart,
          child: child,
        );
      }

      child = InkWell(
        borderRadius:
            isMobileRowDetail ? BorderRadius.circular(12) : BorderRadius.zero,
        onTap: () => _tapCellMobile(context),
        hoverColor: Colors.transparent,
        child: child,
      );
    }

    return BlocProvider.value(
      value: bloc,
      child: Builder(builder: (context) => child),
    );
  }

  void _openOrExpandFile(
    BuildContext context,
    MediaFilePB file,
    List<MediaFilePB> files,
  ) {
    if (file.fileType != MediaFileTypePB.Image) {
      afLaunchUrlString(file.url, context: context);
      return;
    }

    final images =
        files.where((f) => f.fileType == MediaFileTypePB.Image).toList();
    final index = images.indexOf(file);

    showDialog(
      context: context,
      builder: (_) => InteractiveImageViewer(
        userProfile: context.read<MediaCellBloc>().state.userProfile,
        imageProvider: AFBlockImageProvider(
          initialIndex: index,
          images: images
              .map(
                (e) => ImageBlockData(
                  url: e.url,
                  type: e.uploadType.toCustomImageType(),
                ),
              )
              .toList(),
          onDeleteImage: (index) {
            final deleteFile = images[index];
            context.read<MediaCellBloc>().deleteFile(deleteFile.id);
          },
        ),
      ),
    );
  }

  void _tapCellMobile(BuildContext context) {
    final files = context.read<MediaCellBloc>().state.files;

    if (files.isEmpty) {
      showMobileBottomSheet(
        context,
        title: LocaleKeys.grid_media_addFileMobile.tr(),
        showHeader: true,
        showCloseButton: true,
        showDragHandle: true,
        builder: (dContext) => BlocProvider.value(
          value: context.read<MediaCellBloc>(),
          child: MobileMediaUploadSheetContent(
            dialogContext: dContext,
          ),
        ),
      );
      return;
    }

    showMobileBottomSheet(
      context,
      builder: (_) => BlocProvider.value(
        value: context.read<MediaCellBloc>(),
        child: const MobileMediaCellEditor(),
      ),
    );
  }
}

class _FilePreviewRender extends StatelessWidget {
  const _FilePreviewRender({required this.file, required this.extent});

  final MediaFilePB file;

  /// The side of the square the preview is drawn in.
  final double extent;

  @override
  Widget build(BuildContext context) {
    final Widget tile = file.fileType != MediaFileTypePB.Image
        ? Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AFThemeExtension.of(context).greyHover,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: FlowySvg(
                file.fileType.icon,
                size: Size.square((extent * 0.36).clamp(12, 26)),
                color: AFThemeExtension.of(context).textColor,
              ),
            ),
          )
        : Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
            child: AFImage(
              url: file.url,
              uploadType: file.uploadType,
              userProfile: context.read<MediaCellBloc>().state.userProfile,
            ),
          );

    return FlowyTooltip(
      message: file.name,
      child: SizedBox(height: extent, width: extent, child: tile),
    );
  }
}
