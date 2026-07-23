import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_video_download.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/date_time/date_format_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'file_preview_kind.dart';

class FileBlockMenu extends StatefulWidget {
  const FileBlockMenu({
    super.key,
    this.controller,
    this.onClose,
    this.actionContext,
    this.showDownload = true,
    required this.node,
    required this.editorState,
  }) : assert(controller != null || onClose != null);

  final PopoverController? controller;
  final VoidCallback? onClose;
  final BuildContext? actionContext;
  final bool showDownload;
  final Node node;
  final EditorState editorState;

  @override
  State<FileBlockMenu> createState() => _FileBlockMenuState();
}

class _FileBlockMenuState extends State<FileBlockMenu> {
  @override
  Widget build(BuildContext context) {
    final uploadedAtInMS =
        widget.node.attributes[FileBlockKeys.uploadedAt] as int?;
    final uploadedAt = uploadedAtInMS != null
        ? DateTime.fromMillisecondsSinceEpoch(uploadedAtInMS)
        : null;
    final dateFormat = context.read<AppearanceSettingsCubit>().state.dateFormat;
    final urlType =
        FileUrlType.fromIntValue(widget.node.attributes[FileBlockKeys.urlType]);
    final fileUploadType = urlType.toFileUploadTypePB();
    final fileName =
        widget.node.attributes[FileBlockKeys.name] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (filePreviewKindFromName(fileName) != null) ...[
          HoverButton(
            itemHeight: 20,
            leftIcon: const Icon(Icons.preview_outlined, size: 18),
            name: widget.node.attributes[FileBlockKeys.displayMode] == 'preview'
                ? 'Show as file'
                : 'Show preview',
            onTap: () {
              _closeMenu();
              final mode =
                  widget.node.attributes[FileBlockKeys.displayMode] == 'preview'
                      ? 'file'
                      : 'preview';
              final transaction = widget.editorState.transaction
                ..updateNode(
                  widget.node,
                  {FileBlockKeys.displayMode: mode},
                );
              widget.editorState.apply(transaction);
            },
          ),
          const VSpace(4),
        ],
        if (widget.showDownload) ...[
          HoverButton(
            itemHeight: 20,
            leftIcon: const FlowySvg(FlowySvgs.download_s),
            name: LocaleKeys.button_download.tr(),
            onTap: () => unawaited(_download(fileUploadType)),
          ),
          const VSpace(4),
        ],
        HoverButton(
          itemHeight: 20,
          leftIcon: const FlowySvg(FlowySvgs.copy_s),
          name: LocaleKeys.editor_copy.tr(),
          onTap: () => _copyOrShare(copy: true),
        ),
        const VSpace(4),
        HoverButton(
          itemHeight: 20,
          leftIcon: const FlowySvg(FlowySvgs.share_s),
          name: LocaleKeys.button_share.tr(),
          onTap: () => _copyOrShare(copy: false),
        ),
        const VSpace(4),
        HoverButton(
          itemHeight: 20,
          leftIcon: const FlowySvg(FlowySvgs.edit_s),
          name: LocaleKeys.document_plugins_file_renameFile_title.tr(),
          onTap: () => unawaited(_showRenameDialog()),
        ),
        const VSpace(4),
        HoverButton(
          itemHeight: 20,
          leftIcon: const FlowySvg(FlowySvgs.delete_s),
          name: LocaleKeys.button_delete.tr(),
          onTap: () {
            _closeMenu();
            final transaction = widget.editorState.transaction
              ..deleteNode(widget.node);
            widget.editorState.apply(transaction);
          },
        ),
        if (uploadedAt != null) ...[
          const Divider(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FlowyText.regular(
              [FileUrlType.cloud, FileUrlType.local].contains(urlType)
                  ? LocaleKeys.document_plugins_file_uploadedAt.tr(
                      args: [dateFormat.formatDate(uploadedAt, false)],
                    )
                  : LocaleKeys.document_plugins_file_linkedAt.tr(
                      args: [dateFormat.formatDate(uploadedAt, false)],
                    ),
              fontSize: 14,
              maxLines: 2,
              color: Theme.of(context).hintColor,
            ),
          ),
          const VSpace(2),
        ],
      ],
    );
  }

  BuildContext get _actionContext => widget.actionContext ?? context;

  void _closeMenu() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      widget.controller?.close();
    }
  }

  Future<void> _download(FileUploadTypePB fileUploadType) async {
    final actionContext = _actionContext;
    final url = widget.node.attributes[FileBlockKeys.url] as String?;
    final name = widget.node.attributes[FileBlockKeys.name] as String?;
    _closeMenu();
    if (url != null && isYoutubeVideoUrl(url)) {
      await downloadYoutubeVideo(actionContext, url);
      return;
    }
    if (url != null &&
        name != null &&
        fileUploadType != FileUploadTypePB.CloudFile) {
      try {
        if (await downloadMedia(source: url, name: name) &&
            actionContext.mounted) {
          showToastNotification(
            message: LocaleKeys.grid_media_downloadSuccess.tr(),
          );
        }
      } on Exception catch (error) {
        if (actionContext.mounted) {
          showToastNotification(
            message: error.toString(),
            type: ToastificationType.error,
          );
        }
      }
      return;
    }

    final userProfile = widget.editorState.document.root.context
        ?.read<DocumentBloc>()
        .state
        .userProfilePB;
    if (url != null && name != null && actionContext.mounted) {
      final filePB = MediaFilePB(
        url: url,
        name: name,
        uploadType: fileUploadType,
      );
      await downloadMediaFile(
        actionContext,
        filePB,
        userProfile: userProfile,
      );
    }
  }

  Future<void> _showRenameDialog() async {
    final actionContext = _actionContext;
    final node = widget.node;
    final editorState = widget.editorState;
    final nameController = TextEditingController(
      text: node.attributes[FileBlockKeys.name] as String? ?? '',
    );
    nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: nameController.text.length,
    );
    final errorMessage = ValueNotifier<String?>(null);
    BuildContext? renameContext;

    void saveName() {
      if (nameController.text.isEmpty) {
        errorMessage.value =
            LocaleKeys.document_plugins_file_renameFile_nameEmptyError.tr();
        return;
      }
      final transaction = editorState.transaction
        ..updateNode(
          node,
          {FileBlockKeys.name: nameController.text},
        );
      editorState.apply(transaction);
      final dialogContext = renameContext;
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    }

    _closeMenu();
    await Future<void>.delayed(Duration.zero);
    if (!actionContext.mounted) {
      nameController.dispose();
      errorMessage.dispose();
      return;
    }
    await showCustomConfirmDialog(
      context: actionContext,
      title: LocaleKeys.document_plugins_file_renameFile_title.tr(),
      description: LocaleKeys.document_plugins_file_renameFile_description.tr(),
      closeOnConfirm: false,
      builder: (context) {
        renameContext = context;
        return FileRenameTextField(
          nameController: nameController,
          errorMessage: errorMessage,
          onSubmitted: saveName,
          disposeController: false,
        );
      },
      confirmLabel: LocaleKeys.button_save.tr(),
      onConfirm: saveName,
    );
    nameController.dispose();
    errorMessage.dispose();
  }

  Future<void> _copyOrShare({required bool copy}) async {
    final url = widget.node.attributes[FileBlockKeys.url] as String?;
    final name = widget.node.attributes[FileBlockKeys.name] as String?;
    if (url == null || name == null) {
      return;
    }

    final actionContext = _actionContext;
    _closeMenu();
    final urlType = FileUrlType.fromIntValue(
      widget.node.attributes[FileBlockKeys.urlType],
    );
    final shareAsLink =
        urlType == FileUrlType.network && isYoutubeVideoUrl(url);
    try {
      if (copy) {
        await copyMedia(source: url, name: name, shareAsLink: shareAsLink);
      } else {
        await shareMedia(source: url, name: name, shareAsLink: shareAsLink);
      }
      if (copy && actionContext.mounted) {
        showToastNotification(message: LocaleKeys.message_copy_success.tr());
      }
    } on Exception catch (error) {
      if (actionContext.mounted) {
        showToastNotification(
          message: error.toString(),
          type: ToastificationType.error,
        );
      }
    }
  }
}

class FileRenameTextField extends StatefulWidget {
  const FileRenameTextField({
    super.key,
    required this.nameController,
    required this.errorMessage,
    required this.onSubmitted,
    this.disposeController = true,
  });

  final TextEditingController nameController;
  final ValueNotifier<String?> errorMessage;
  final VoidCallback onSubmitted;

  final bool disposeController;

  @override
  State<FileRenameTextField> createState() => _FileRenameTextFieldState();
}

class _FileRenameTextFieldState extends State<FileRenameTextField> {
  @override
  void initState() {
    super.initState();
    widget.errorMessage.addListener(_setState);
  }

  @override
  void dispose() {
    widget.errorMessage.removeListener(_setState);
    if (widget.disposeController) {
      widget.nameController.dispose();
    }
    super.dispose();
  }

  void _setState() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyTextField(
          controller: widget.nameController,
          onSubmitted: (_) => widget.onSubmitted(),
        ),
        if (widget.errorMessage.value != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FlowyText(
              widget.errorMessage.value!,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}
