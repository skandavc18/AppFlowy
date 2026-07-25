import 'dart:async';

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WorkspaceCoverActions extends StatefulWidget {
  const WorkspaceCoverActions({
    super.key,
    required this.workspace,
    this.userProfile,
    this.generateDefaultWhenMissing = false,
    this.onCoverChanged,
  });

  final UserWorkspacePB workspace;
  final UserProfilePB? userProfile;
  final bool generateDefaultWhenMissing;
  final ValueChanged<PageStyleCover?>? onCoverChanged;

  @override
  State<WorkspaceCoverActions> createState() => _WorkspaceCoverActionsState();
}

class _WorkspaceCoverActionsState extends State<WorkspaceCoverActions> {
  final coverPopoverController = PopoverController();
  PageStyleCover? cover;
  bool saving = false;
  bool defaultPersistenceScheduled = false;

  @override
  void initState() {
    super.initState();
    cover = _resolvedCover();
    _scheduleDefaultPersistence();
  }

  @override
  void didUpdateWidget(covariant WorkspaceCoverActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.workspaceId != widget.workspace.workspaceId ||
        oldWidget.workspace.cover != widget.workspace.cover) {
      defaultPersistenceScheduled = false;
      cover = _resolvedCover();
      _scheduleDefaultPersistence();
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _canEdit
        ? Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AppFlowyPopover(
                controller: coverPopoverController,
                direction: PopoverDirection.bottomWithLeftAligned,
                offset: const Offset(0, 8),
                margin: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  maxWidth: 540,
                  maxHeight: 360,
                  minHeight: 80,
                ),
                child: DecorationActionButton(
                  icon: FlowySvgs.add_cover_s,
                  label: cover == null || cover!.isNone
                      ? LocaleKeys.document_plugins_cover_addCover.tr()
                      : LocaleKeys.document_plugins_cover_changeCover.tr(),
                ),
                popupBuilder: (_) => UploadImageMenu(
                  limitMaximumImageSize:
                      widget.workspace.workspaceType == WorkspaceTypePB.ServerW,
                  supportTypes: const [
                    UploadImageType.color,
                    UploadImageType.local,
                    UploadImageType.url,
                    UploadImageType.unsplash,
                  ],
                  onSelectedLocalImages: (files) async {
                    if (files.isNotEmpty) {
                      await _saveLocalSelection(files.first.path);
                    }
                  },
                  onSelectedNetworkImage: (url) => _saveCover(
                    PageStyleCover(
                      type: PageStyleCoverImageType.unsplashImage,
                      value: url,
                    ),
                  ),
                  onSelectedColor: (color) => _saveCover(
                    PageStyleCover(
                      type: PageStyleCoverImageType.pureColor,
                      value: color,
                    ),
                  ),
                  onSelectedAIImage: (_) {
                    Log.warn(
                      'AI image selection is not enabled for workspace covers',
                    );
                  },
                ),
              ),
              if (cover != null && !cover!.isNone)
                DecorationActionButton(
                  icon: FlowySvgs.delete_s,
                  label: LocaleKeys.document_plugins_cover_removeCover.tr(),
                  onTap: () => _saveCover(const PageStyleCover.none()),
                ),
            ],
          )
        : const SizedBox.shrink();
    return actions;
  }

  Future<void> _saveLocalSelection(String path) async {
    final PageStyleCoverImageType type;
    final String? value;
    String? errorMessage;
    if (widget.workspace.workspaceType == WorkspaceTypePB.ServerW) {
      (value, errorMessage) = await saveImageToCloudStorage(
        path,
        widget.workspace.workspaceId,
      );
      type = PageStyleCoverImageType.customImage;
    } else {
      value = await saveImageToLocalStorage(path);
      type = PageStyleCoverImageType.localImage;
    }
    if (!mounted) {
      return;
    }
    if (value == null) {
      showSnapBar(
        context,
        errorMessage ??
            LocaleKeys.document_plugins_image_imageUploadFailed.tr(),
      );
      return;
    }

    await _saveCover(PageStyleCover(type: type, value: value));
  }

  PageStyleCover? _resolvedCover() {
    final storedCover = WorkspaceCoverCodec.decode(widget.workspace.cover);
    if (storedCover != null ||
        !widget.generateDefaultWhenMissing ||
        widget.workspace.cover.trim().isNotEmpty) {
      return storedCover;
    }
    return AutomaticViewCover.forWorkspace(name: widget.workspace.name);
  }

  bool get _canEdit =>
      widget.workspace.workspaceType == WorkspaceTypePB.LocalW ||
      widget.workspace.role == AFRolePB.Owner;

  void _scheduleDefaultPersistence() {
    if (!widget.generateDefaultWhenMissing ||
        defaultPersistenceScheduled ||
        widget.workspace.cover.trim().isNotEmpty ||
        !_canEdit) {
      return;
    }

    defaultPersistenceScheduled = true;
    final workspaceId = widget.workspace.workspaceId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.workspace.workspaceId != workspaceId ||
          widget.workspace.cover.trim().isNotEmpty) {
        return;
      }
      unawaited(
        _saveCover(
          AutomaticViewCover.forWorkspace(name: widget.workspace.name),
          force: true,
        ),
      );
    });
  }

  Future<void> _saveCover(
    PageStyleCover nextCover, {
    bool force = false,
  }) async {
    coverPopoverController.close();
    if (saving || (!force && nextCover == cover)) {
      return;
    }

    final previousCover = cover;
    final bloc = context.read<UserWorkspaceBloc>();
    final completion = bloc.stream.firstWhere(
      (state) =>
          state.actionResult?.actionType == WorkspaceActionType.updateCover &&
          state.actionResult?.isLoading == false,
    );
    setState(() {
      saving = true;
      cover = nextCover;
    });
    widget.onCoverChanged?.call(nextCover);
    bloc.add(
      UserWorkspaceEvent.updateWorkspaceCover(
        workspaceId: widget.workspace.workspaceId,
        cover: WorkspaceCoverCodec.encode(nextCover),
      ),
    );

    final result = (await completion).actionResult?.result;
    if (!mounted) {
      return;
    }
    result?.onFailure((error) => showSnapBar(context, error.msg));
    final shouldRestore = result == null || result.isFailure;
    setState(() {
      saving = false;
      if (shouldRestore) {
        cover = previousCover;
      }
    });
    if (shouldRestore) {
      widget.onCoverChanged?.call(previousCover);
    }
  }
}
