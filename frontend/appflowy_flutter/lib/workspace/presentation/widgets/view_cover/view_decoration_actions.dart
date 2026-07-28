import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_cover_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/cover_image_download.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flutter/material.dart';
import 'package:protobuf/protobuf.dart';

class ViewDecorationActions extends StatefulWidget {
  const ViewDecorationActions({
    super.key,
    required this.view,
    this.userProfile,
    this.onViewChanged,
    this.showCoverAction = true,
    this.showIconAction = true,
    this.visible = true,
  });

  final ViewPB view;
  final UserProfilePB? userProfile;
  final ValueChanged<ViewPB>? onViewChanged;
  final bool showCoverAction;
  final bool showIconAction;
  final bool visible;

  @override
  State<ViewDecorationActions> createState() => _ViewDecorationActionsState();
}

class _ViewDecorationActionsState extends State<ViewDecorationActions> {
  final coverPopoverController = PopoverController();
  bool coverPopoverOpen = false;
  bool iconPopoverOpen = false;

  @override
  Widget build(BuildContext context) {
    final isVisible = widget.visible || coverPopoverOpen || iconPopoverOpen;
    return IgnorePointer(
      ignoring: !isVisible,
      child: AnimatedOpacity(
        key: const ValueKey('view-decoration-actions-opacity'),
        opacity: isVisible ? 1 : 0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (widget.showIconAction)
              ViewIconPicker(
                view: widget.view,
                onViewChanged: widget.onViewChanged,
                onOpenChanged: _setIconPopoverOpen,
                child: DecorationActionButton(
                  icon: FlowySvgs.add_icon_s,
                  label: widget.view.icon.value.isEmpty
                      ? LocaleKeys.document_plugins_cover_addIcon.tr()
                      : LocaleKeys.document_plugins_cover_changeIcon.tr(),
                ),
              ),
            if (widget.showCoverAction)
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
                onOpen: () => _setCoverPopoverOpen(true),
                onClose: () => _setCoverPopoverOpen(false),
                child: DecorationActionButton(
                  icon: FlowySvgs.add_cover_s,
                  label: widget.view.cover == null || widget.view.cover!.isNone
                      ? LocaleKeys.document_plugins_cover_addCover.tr()
                      : LocaleKeys.document_plugins_cover_changeCover.tr(),
                ),
                popupBuilder: (_) => UploadImageMenu(
                  limitMaximumImageSize: widget.userProfile?.workspaceType ==
                      WorkspaceTypePB.ServerW,
                  supportTypes: const [
                    UploadImageType.color,
                    UploadImageType.local,
                    UploadImageType.url,
                    UploadImageType.unsplash,
                  ],
                  onSelectedLocalImages: (files) async {
                    if (files.isEmpty) {
                      return;
                    }
                    await _saveLocalSelection(files.first.path);
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
                      'AI image selection is not enabled for view covers',
                    );
                  },
                ),
              ),
            if (widget.showCoverAction && _downloadableCover != null)
              DecorationActionButton(
                icon: FlowySvgs.download_s,
                label: LocaleKeys.document_plugins_cover_downloadCover.tr(),
                onTap: _downloadCover,
              ),
            if (widget.showCoverAction &&
                widget.view.cover != null &&
                !widget.view.cover!.isNone)
              DecorationActionButton(
                icon: FlowySvgs.delete_s,
                label: LocaleKeys.document_plugins_cover_removeCover.tr(),
                onTap: () => _saveCover(const PageStyleCover.none()),
              ),
          ],
        ),
      ),
    );
  }

  DownloadableCoverImage? get _downloadableCover =>
      DownloadableCoverImage.fromPageStyleCover(widget.view.cover);

  Future<void> _downloadCover() async {
    final cover = _downloadableCover;
    if (cover == null) {
      return;
    }
    await downloadCoverImage(cover, userProfile: widget.userProfile);
  }

  void _setCoverPopoverOpen(bool value) {
    if (coverPopoverOpen == value || !mounted) {
      return;
    }
    setState(() => coverPopoverOpen = value);
  }

  void _setIconPopoverOpen(bool value) {
    if (iconPopoverOpen == value || !mounted) {
      return;
    }
    setState(() => iconPopoverOpen = value);
  }

  Future<void> _saveLocalSelection(String path) async {
    final profileResult = await UserBackendService.getCurrentUserProfile();
    if (!mounted) {
      return;
    }

    final profile = profileResult.fold<UserProfilePB?>(
      (profile) => profile,
      (error) {
        showSnapBar(context, error.msg);
        return null;
      },
    );
    if (profile == null) {
      return;
    }

    final PageStyleCoverImageType type;
    final String? value;
    if (profile.workspaceType == WorkspaceTypePB.ServerW) {
      (value, _) = await saveImageToCloudStorage(path, widget.view.id);
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
        LocaleKeys.document_plugins_image_imageUploadFailed.tr(),
      );
      return;
    }

    await _saveCover(PageStyleCover(type: type, value: value));
  }

  Future<void> _saveCover(PageStyleCover cover) async {
    coverPopoverController.close();
    final previous = widget.view.cover;
    final result = await ViewCoverService.updateCover(
      view: widget.view,
      cover: cover,
    );
    if (!mounted) {
      return;
    }

    await result.fold(
      (_) async {
        widget.onViewChanged?.call(_updatedView(cover: cover));
        await _removeReplacedCover(previous, cover);
      },
      (error) async => showSnapBar(context, error.msg),
    );
  }

  ViewPB _updatedView({
    PageStyleCover? cover,
  }) {
    widget.view.freeze();
    return widget.view.rebuild((updated) {
      if (cover != null) {
        updated.extra = ViewCoverCodec.mergeCover(widget.view.extra, cover);
      }
    });
  }

  Future<void> _removeReplacedCover(
    PageStyleCover? previous,
    PageStyleCover replacement,
  ) async {
    if (previous == null ||
        previous.isNone ||
        previous.value.isEmpty ||
        previous.value == replacement.value) {
      return;
    }

    if (previous.isLocalImage) {
      await deleteImageFromLocalStorage(previous.value);
    } else if (previous.isCustomImage) {
      final deleteResult = await DocumentEventDeleteFile(
        DeleteFilePB(url: previous.value),
      ).send();
      deleteResult.onFailure(
        (error) => Log.error(
          'Unable to delete replaced cover ${previous.value}: ${error.msg}',
        ),
      );
    }
  }
}

class ViewIconPicker extends StatefulWidget {
  const ViewIconPicker({
    super.key,
    required this.view,
    required this.child,
    this.onViewChanged,
    this.onOpenChanged,
    this.direction = PopoverDirection.bottomWithLeftAligned,
  });

  final ViewPB view;
  final Widget child;
  final ValueChanged<ViewPB>? onViewChanged;
  final ValueChanged<bool>? onOpenChanged;
  final PopoverDirection direction;

  @override
  State<ViewIconPicker> createState() => _ViewIconPickerState();
}

class _ViewIconPickerState extends State<ViewIconPicker> {
  final controller = PopoverController();

  @override
  Widget build(BuildContext context) {
    final tooltip = widget.view.icon.value.isEmpty
        ? LocaleKeys.document_plugins_cover_addIcon.tr()
        : LocaleKeys.document_plugins_cover_changeIcon.tr();
    return AppFlowyPopover(
      controller: controller,
      direction: widget.direction,
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      constraints: BoxConstraints.loose(const Size(360, 380)),
      clickHandler: PopoverClickHandler.gestureDetector,
      onOpen: () => widget.onOpenChanged?.call(true),
      onClose: () => widget.onOpenChanged?.call(false),
      child: Semantics(
        button: true,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: widget.child,
          ),
        ),
      ),
      popupBuilder: (_) => FlowyIconEmojiPicker(
        documentId: widget.view.id,
        initialType: widget.view.icon.toEmojiIconData().type.toPickerTabType(),
        tabs: const [
          PickerTabType.emoji,
          PickerTabType.icon,
          PickerTabType.custom,
        ],
        onSelectedEmoji: (result) async {
          final update = await ViewBackendService.updateViewIcon(
            view: widget.view,
            viewIcon: result.data,
          );
          if (!mounted) {
            return;
          }
          update.fold(
            (_) {
              widget.view.freeze();
              final updated = widget.view.rebuild(
                (view) => view.icon = result.data.toViewIcon(),
              );
              widget.onViewChanged?.call(updated);
              if (!result.keepOpen) {
                controller.close();
              }
            },
            (error) => showSnapBar(context, error.msg),
          );
        },
      ),
    );
  }
}

class DecorationActionButton extends StatelessWidget {
  const DecorationActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final FlowySvgData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    return _HoverAction(
      onTap: onTap,
      builder: (hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: hovered
              ? EditorSurfaceStyle.calloutBackgroundFor(
                  theme.brightness,
                  theme.colorScheme.surfaceContainerHighest,
                  isPaper: isPaper,
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowySvg(
              icon,
              size: const Size.square(18),
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoverAction extends StatefulWidget {
  const _HoverAction({
    required this.builder,
    this.onTap,
  });

  final Widget Function(bool hovered) builder;
  final VoidCallback? onTap;

  @override
  State<_HoverAction> createState() => _HoverActionState();
}

class _HoverActionState extends State<_HoverAction> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(hovered),
      ),
    );
  }
}
