import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/media_cell_bloc.dart';
import 'package:appflowy/plugins/database/grid/application/row/row_detail_bloc.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_skeleton/media.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/media_cell_editor.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/plugins/document/presentation/editor_drop_manager.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_upload_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/util/xfile_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/file_viewer/attachment_file_viewer.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reorderables/reorderables.dart';

const _dropFileKey = 'files_media';
const _itemWidth = 86.4;

class DekstopRowDetailMediaCellSkin extends IEditableMediaCellSkin {
  final mutex = PopoverMutex();

  @override
  void dispose() {
    mutex.dispose();
  }

  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    PopoverController popoverController,
    MediaCellBloc bloc,
  ) {
    return BlocProvider.value(
      value: bloc,
      child: BlocBuilder<MediaCellBloc, MediaCellState>(
        builder: (context, state) => LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <= 16) {
              return const SizedBox.shrink();
            }
            if (state.files.isEmpty) {
              return _AddFileButton(
                controller: popoverController,
                direction: PopoverDirection.bottomWithLeftAligned,
                mutex: mutex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: FlowyText(
                    LocaleKeys.grid_row_textPlaceholder.tr(),
                    color: Theme.of(context).hintColor,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }

            final rowWidth = math.max(0.0, constraints.maxWidth - 16);
            double widthFor(MediaFilePB file) =>
                math.min(file.isImage ? _itemWidth : 200.0, rowWidth);
            // Pack the actual widths into two rows. The footer replaces the
            // last slot with the same width, preserving order and its count.
            var capacity = state.files.length;
            if (!state.showAllFiles && rowWidth.isFinite) {
              var row = 0;
              var usedWidth = 0.0;
              capacity = 0;
              for (final file in state.files) {
                final width = widthFor(file);
                if (usedWidth > 0 && usedWidth + 8 + width > rowWidth + 0.01) {
                  row++;
                  usedWidth = 0;
                }
                if (row == 2) break;
                usedWidth += (usedWidth > 0 ? 8 : 0) + width;
                capacity++;
              }
            }
            final collapsed = capacity < state.files.length;
            final visibleCount = collapsed ? capacity - 1 : state.files.length;
            final filesToDisplay = state.files.take(visibleCount).toList();
            // The file under the +N footer is hidden too.
            final extraCount = state.files.length - visibleCount;
            final images = state.files.where((file) => file.isImage).toList();
            return _AddFileButton(
              controller: popoverController,
              mutex: mutex,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ReorderableWrap(
                      needsLongPressDraggable: false,
                      runSpacing: 8,
                      spacing: 8,
                      onReorder: (from, to) => context
                          .read<MediaCellBloc>()
                          .add(MediaCellEvent.reorderFiles(from: from, to: to)),
                      footer: collapsed
                          ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _toggleShowAllFiles(context),
                              child: _FilePreviewRender(
                                key: ValueKey(state.files[visibleCount].id),
                                file: state.files[visibleCount],
                                images: images,
                                width: widthFor(state.files[visibleCount]),
                                mutex: mutex,
                                hideFileNames: state.hideFileNames,
                                foregroundText: LocaleKeys.grid_media_extraCount
                                    .tr(args: [extraCount.toString()]),
                              ),
                            )
                          : null,
                      buildDraggableFeedback: (_, __, child) =>
                          BlocProvider.value(
                        value: context.read<MediaCellBloc>(),
                        child: _FilePreviewFeedback(child: child),
                      ),
                      children: filesToDisplay
                          .map(
                            (file) => _FilePreviewRender(
                              key: ValueKey(file.id),
                              file: file,
                              images: images,
                              width: widthFor(file),
                              mutex: mutex,
                              hideFileNames: state.hideFileNames,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  if (constraints.maxWidth >= 32)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FlowySvg(
                            FlowySvgs.add_thin_s,
                            size: const Size.square(12),
                            color: Theme.of(context).hintColor,
                          ),
                          const HSpace(6),
                          Flexible(
                            child: FlowyText.medium(
                              LocaleKeys.grid_media_addFileOrImage.tr(),
                              fontSize: 12,
                              color: Theme.of(context).hintColor,
                              figmaLineHeight: 18,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _toggleShowAllFiles(BuildContext context) {
    context
        .read<MediaCellBloc>()
        .add(const MediaCellEvent.toggleShowAllFiles());
  }
}

class _FilePreviewFeedback extends StatelessWidget {
  const _FilePreviewFeedback({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          width: 2,
          color: const Color(0xFF00BCF0),
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1F2329).withValues(alpha: .2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: BlocProvider.value(
          value: context.read<MediaCellBloc>(),
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ),
    );
  }
}

const _menuWidth = 350.0;

class _AddFileButton extends StatefulWidget {
  const _AddFileButton({
    this.mutex,
    required this.controller,
    this.direction = PopoverDirection.bottomWithCenterAligned,
    required this.child,
  });

  final PopoverController controller;
  final PopoverMutex? mutex;
  final PopoverDirection direction;
  final Widget child;

  @override
  State<_AddFileButton> createState() => _AddFileButtonState();
}

class _AddFileButtonState extends State<_AddFileButton> {
  Offset? position;

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      triggerActions: PopoverTriggerFlags.none,
      controller: widget.controller,
      mutex: widget.mutex,
      offset: const Offset(0, 10),
      direction: widget.direction,
      constraints: const BoxConstraints(maxWidth: _menuWidth),
      margin: EdgeInsets.zero,
      asBarrier: true,
      onClose: () =>
          context.read<EditorDropManagerState>().remove(_dropFileKey),
      popupBuilder: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<EditorDropManagerState>().add(_dropFileKey);
        });

        return FileUploadMenu(
          allowMultipleFiles: true,
          onInsertLocalFile: (files) => insertLocalFiles(
            context,
            files,
            userProfile: context.read<MediaCellBloc>().state.userProfile,
            documentId: context.read<MediaCellBloc>().rowId,
            onUploadSuccess: (file, path, isLocalMode) {
              final mediaCellBloc = context.read<MediaCellBloc>();
              if (mediaCellBloc.isClosed) {
                return;
              }

              mediaCellBloc.add(
                MediaCellEvent.addFile(
                  url: path,
                  name: file.name,
                  uploadType: isLocalMode
                      ? FileUploadTypePB.LocalFile
                      : FileUploadTypePB.CloudFile,
                  fileType: file.fileType.toMediaFileTypePB(),
                ),
              );

              widget.controller.close();
            },
          ),
          onInsertNetworkFile: (url) {
            if (url.isEmpty) return;
            final uri = Uri.tryParse(url);
            if (uri == null) {
              return;
            }

            MediaFileTypePB fileType = inferFileType(url).toMediaFileTypePB();
            fileType = fileType == MediaFileTypePB.Other
                ? MediaFileTypePB.Link
                : fileType;

            String name =
                uri.pathSegments.isNotEmpty ? uri.pathSegments.last : "";
            if (name.isEmpty && uri.pathSegments.length > 1) {
              name = uri.pathSegments[uri.pathSegments.length - 2];
            } else if (name.isEmpty) {
              name = uri.host;
            }

            context.read<MediaCellBloc>().add(
                  MediaCellEvent.addFile(
                    url: url,
                    name: name,
                    uploadType: FileUploadTypePB.NetworkFile,
                    fileType: fileType,
                  ),
                );

            widget.controller.close();
          },
        );
      },
      child: MouseRegion(
        onEnter: (event) => position = event.position,
        onExit: (_) => position = null,
        onHover: (event) => position = event.position,
        child: GestureDetector(
          onTap: () {
            if (position != null) {
              widget.controller.showAt(
                position! - const Offset(_menuWidth / 2, 0),
              );
            }
          },
          behavior: HitTestBehavior.translucent,
          child: FlowyHover(resetHoverOnRebuild: false, child: widget.child),
        ),
      ),
    );
  }
}

class _FilePreviewRender extends StatefulWidget {
  const _FilePreviewRender({
    super.key,
    required this.file,
    required this.images,
    required this.width,
    required this.mutex,
    this.hideFileNames = false,
    this.foregroundText,
  });

  final MediaFilePB file;
  final List<MediaFilePB> images;
  final double width;
  final PopoverMutex mutex;
  final bool hideFileNames;
  final String? foregroundText;

  @override
  State<_FilePreviewRender> createState() => _FilePreviewRenderState();
}

class _FilePreviewRenderState extends State<_FilePreviewRender> {
  final nameController = TextEditingController();
  final controller = PopoverController();
  bool isHovering = false;
  bool isSelected = false;

  MediaFilePB get file => widget.file;

  @override
  void dispose() {
    nameController.dispose();
    controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = PremiumThemeExtension.maybeOf(context);
    final surface = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      palette?.surface ?? theme.colorScheme.surfaceContainerLow,
      isPaper: PaperTheme.isEnabled(context),
    );
    Widget child = file.isImage
        ? MediaFileThumbnail(
            file: file,
            size: Size(widget.width, 68),
            userProfile: context.read<MediaCellBloc>().state.userProfile,
            borderRadius: BorderRadius.only(
              topLeft: Corners.s5Radius,
              topRight: Corners.s5Radius,
              bottomLeft: widget.hideFileNames ? Corners.s5Radius : Radius.zero,
              bottomRight:
                  widget.hideFileNames ? Corners.s5Radius : Radius.zero,
            ),
          )
        : MediaFileLabel(
            file: file,
            onTap: widget.foregroundText == null ? _openOrExpandFile : null,
            trailingInset: widget.width >= 64 ? 24 : 0,
          );

    if (widget.foregroundText != null) {
      child = Stack(
        children: [
          if (!file.isImage)
            ExcludeSemantics(
              child: TooltipVisibility(
                visible: false,
                child: IgnorePointer(child: child),
              ),
            ),
          if (file.isImage)
            Positioned.fill(
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration:
                    BoxDecoration(color: Colors.black.withValues(alpha: 0.5)),
                child: child,
              ),
            ),
          Positioned.fill(
            child: ColoredBox(
              color: file.isImage ? Colors.transparent : surface,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: FlowyText.semibold(
                    widget.foregroundText!,
                    color: file.isImage
                        ? Colors.white
                        : palette?.textPrimary ?? theme.colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: widget.foregroundText ?? file.displayName,
        child: AppFlowyPopover(
          controller: controller,
          constraints: const BoxConstraints(maxWidth: 240),
          offset: const Offset(0, 5),
          triggerActions: PopoverTriggerFlags.none,
          onClose: () => setState(() => isSelected = false),
          asBarrier: true,
          popupBuilder: (popoverContext) => MultiBlocProvider(
            providers: [
              BlocProvider.value(value: context.read<RowDetailBloc>()),
              BlocProvider.value(value: context.read<MediaCellBloc>()),
            ],
            child: _FileMenu(
              parentContext: context,
              file: file,
              images: widget.images,
              controller: controller,
              nameController: nameController,
            ),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: file.isImage && widget.foregroundText == null
                ? _openOrExpandFile
                : null,
            child: Container(
              width: widget.width,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Corners.s6Radius),
                border:
                    file.isImage ? Border.all(color: theme.dividerColor) : null,
                color: file.isImage ? theme.cardColor : null,
              ),
              child: Stack(
                children: [
                  if (!file.isImage)
                    child
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 68, child: child),
                        if (!widget.hideFileNames)
                          Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: FlowyText(
                                    file.displayName,
                                    fontSize: 10,
                                    overflow: TextOverflow.ellipsis,
                                    figmaLineHeight: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  if (widget.foregroundText == null &&
                      widget.width >= 24 &&
                      (isHovering || isSelected))
                    Positioned(
                      top: 3,
                      right: 3,
                      child: FlowyIconButton(
                        onPressed: () {
                          setState(() => isSelected = true);
                          controller.show();
                        },
                        fillColor: file.isImage
                            ? Colors.black.withValues(alpha: 0.4)
                            : surface,
                        width: 18,
                        radius: BorderRadius.circular(4),
                        icon: FlowySvg(
                          FlowySvgs.three_dots_s,
                          color: file.isImage
                              ? Colors.white
                              : palette?.textSecondary ??
                                  theme.colorScheme.onSurfaceVariant,
                          size: const Size.square(16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openOrExpandFile() {
    final bloc = context.read<MediaCellBloc>();
    if (!file.isImage) {
      unawaited(
        showAttachmentFileViewer(
          context,
          file,
          userProfile: bloc.state.userProfile,
        ),
      );
      return;
    }

    // Navigation and the explicit delete callback must use the same snapshot,
    // even if the cell receives another file list while the dialog is open.
    final images = List<MediaFilePB>.of(widget.images);
    showDialog(
      context: context,
      builder: (_) => InteractiveImageViewer(
        userProfile: bloc.state.userProfile,
        imageProvider: MediaFileImageProvider(
          files: images,
          initialFileId: file.id,
          onDeleteImage: (index) {
            if (!bloc.isClosed) bloc.deleteFile(images[index].id);
          },
        ),
      ),
    );
  }
}

class _FileMenu extends StatefulWidget {
  const _FileMenu({
    required this.parentContext,
    required this.file,
    required this.images,
    required this.controller,
    required this.nameController,
  });

  /// Parent [BuildContext] used to retrieve the [MediaCellBloc]
  final BuildContext parentContext;

  /// The current [MediaFilePB] being previewed
  final MediaFilePB file;

  /// All images in the field, excluding non-image files-
  final List<MediaFilePB> images;

  /// The [PopoverController] to close the popover
  final PopoverController controller;

  /// The [TextEditingController] for renaming the file
  final TextEditingController nameController;

  @override
  State<_FileMenu> createState() => _FileMenuState();
}

class _FileMenuState extends State<_FileMenu> {
  final errorMessage = ValueNotifier<String?>(null);

  @override
  void dispose() {
    errorMessage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SeparatedColumn(
      separatorBuilder: () => const VSpace(8),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.file.isImage) ...[
          MediaMenuItem(
            onTap: () {
              _showInteractiveViewer();
              widget.controller.close();
            },
            icon: FlowySvgs.full_view_s,
            label: LocaleKeys.grid_media_expand.tr(),
          ),
          MediaMenuItem(
            onTap: () {
              widget.controller.close();
              _setCover(context);
            },
            icon: FlowySvgs.cover_s,
            label: LocaleKeys.grid_media_setAsCover.tr(),
          ),
        ],
        MediaMenuItem(
          onTap: () {
            widget.controller.close();
            afLaunchUrlString(widget.file.url);
          },
          icon: FlowySvgs.open_in_browser_s,
          label: LocaleKeys.grid_media_openInBrowser.tr(),
        ),
        MediaMenuItem(
          onTap: () {
            widget.controller.close();
            widget.nameController.text = widget.file.name;
            widget.nameController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: widget.nameController.text.length,
            );

            _showRenameConfirmDialog();
          },
          icon: FlowySvgs.rename_s,
          label: LocaleKeys.grid_media_rename.tr(),
        ),
        if (widget.file.uploadType == FileUploadTypePB.CloudFile) ...[
          MediaMenuItem(
            onTap: () async => downloadMediaFile(
              context,
              widget.file,
              userProfile: context.read<MediaCellBloc>().state.userProfile,
            ),
            icon: FlowySvgs.save_as_s,
            label: LocaleKeys.button_download.tr(),
          ),
        ],
        MediaMenuItem(
          onTap: () {
            widget.controller.close();
            showConfirmDeletionDialog(
              context: context,
              name: widget.file.name,
              description: LocaleKeys.grid_media_deleteFileDescription.tr(),
              onConfirm: () => widget.parentContext
                  .read<MediaCellBloc>()
                  .add(MediaCellEvent.removeFile(fileId: widget.file.id)),
            );
          },
          icon: FlowySvgs.trash_s,
          label: LocaleKeys.button_delete.tr(),
        ),
      ],
    );
  }

  void _saveName(BuildContext context) {
    final newName = widget.nameController.text.trim();
    if (newName.isEmpty) {
      return;
    }

    context
        .read<MediaCellBloc>()
        .add(MediaCellEvent.renameFile(fileId: widget.file.id, name: newName));
    Navigator.of(context).pop();
  }

  void _showRenameConfirmDialog() {
    showCustomConfirmDialog(
      context: widget.parentContext,
      title: LocaleKeys.document_plugins_file_renameFile_title.tr(),
      description: LocaleKeys.document_plugins_file_renameFile_description.tr(),
      closeOnConfirm: false,
      builder: (builderContext) => FileRenameTextField(
        nameController: widget.nameController,
        errorMessage: errorMessage,
        onSubmitted: () => _saveName(widget.parentContext),
        disposeController: false,
      ),
      style: ConfirmPopupStyle.cancelAndOk,
      confirmLabel: LocaleKeys.button_save.tr(),
      onConfirm: () => _saveName(widget.parentContext),
      onCancel: Navigator.of(widget.parentContext).pop,
    );
  }

  void _setCover(BuildContext context) => context.read<RowDetailBloc>().add(
        RowDetailEvent.setCover(
          RowCoverPB(
            data: widget.file.url,
            uploadType: widget.file.uploadType,
            coverType: CoverTypePB.FileCover,
          ),
        ),
      );

  void _showInteractiveViewer() {
    final bloc = widget.parentContext.read<MediaCellBloc>();
    final images = List<MediaFilePB>.of(widget.images);
    showDialog(
      context: widget.parentContext,
      builder: (_) => InteractiveImageViewer(
        userProfile: bloc.state.userProfile,
        imageProvider: MediaFileImageProvider(
          initialFileId: widget.file.id,
          files: images,
          onDeleteImage: (index) {
            if (!bloc.isClosed) bloc.deleteFile(images[index].id);
          },
        ),
      ),
    );
  }
}
