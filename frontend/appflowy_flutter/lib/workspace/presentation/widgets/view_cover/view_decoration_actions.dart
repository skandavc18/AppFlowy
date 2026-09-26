import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_cover_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/cover_image_download.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:protobuf/protobuf.dart';

/// Storage boundaries for cover actions; the default keeps the existing services.
class ViewCoverActionsBackend {
  const ViewCoverActionsBackend();

  Future<FlowyResult<UserProfilePB, FlowyError>> currentUser() =>
      UserBackendService.getCurrentUserProfile();

  Future<ViewCoverUpload?> upload({
    required String path,
    required ViewPB view,
    required UserProfilePB profile,
  }) async {
    if (profile.workspaceType == WorkspaceTypePB.ServerW) {
      final (value, _) = await saveImageToCloudStorage(path, view.id);
      // Cloud storage can reuse a content-addressed asset. Its response does
      // not prove ownership, so an abandoned upload must not delete that URL.
      return value == null
          ? null
          : ViewCoverUpload(
              cover: PageStyleCover(
                type: PageStyleCoverImageType.customImage,
                value: value,
              ),
            );
    }
    final value = await saveImageToLocalStorage(path);
    return value == null
        ? null
        : ViewCoverUpload(
            cover: PageStyleCover(
              type: PageStyleCoverImageType.localImage,
              value: value,
            ),
            // The local service copies to a fresh UUID, never the source file.
            newlyCreated: true,
          );
  }

  /// A failure result rejects the write; a thrown error has an unknown outcome.
  Future<FlowyResult<void, FlowyError>> save({
    required ViewPB view,
    required PageStyleCover cover,
  }) =>
      ViewCoverService.updateCover(view: view, cover: cover);

  Future<void> delete(PageStyleCover cover) async {
    if (cover.isLocalImage) {
      await deleteImageFromLocalStorage(cover.value);
    } else if (cover.isCustomImage) {
      final result = await DocumentEventDeleteFile(
        DeleteFilePB(url: cover.value),
      ).send();
      result.onFailure(
        (error) => Log.error('Unable to delete cover asset: ${error.msg}'),
      );
    }
  }
}

class ViewCoverUpload {
  const ViewCoverUpload({required this.cover, this.newlyCreated = false});

  final PageStyleCover cover;

  /// True only for an exclusively owned new asset, not a reused URL or source.
  final bool newlyCreated;
}

/// Presentation slots from one action owner. Empty groups are null so a page
/// does not reserve a hidden toolbar row. [WorkspacePageIdentity] hosts the
/// icon/add-cover group; [WorkspacePageHeader] hosts the cover overlay group.
typedef PageDecorationLayoutBuilder = Widget Function(
  Widget? iconActions,
  Widget? coverActions,
  Widget? pageActions,
);

class ViewDecorationActions extends StatefulWidget {
  const ViewDecorationActions({
    super.key,
    required this.view,
    this.userProfile,
    this.onViewChanged,
    this.showCoverAction = true,
    this.showIconAction = true,
    this.visible = true,
    this.leading,
    this.children = const [],
    this.layoutBuilder,
    this.hasCover,
    this.showDownloadAction,
    this.markCoverChosen = false,
    this.coverBackend = const ViewCoverActionsBackend(),
  });

  final ViewPB view;
  final UserProfilePB? userProfile;
  final ValueChanged<ViewPB>? onViewChanged;

  /// Hosts enforce page access through these gates; revocation cancels work.
  final bool showCoverAction;
  final bool showIconAction;

  /// Reveal policy only, not permission. Missing and saved decorations follow
  /// the same header hover, focus, touch and accessibility policy. Standalone
  /// rows retain the caller's explicit reveal policy.
  final bool visible;

  /// Always-visible navigation sharing the row, outside the action-group fade.
  final Widget? leading;

  /// Page controls placed before the automatic icon/cover actions in the same
  /// wrapping reveal row. Supply individual controls, not another toolbar.
  final List<Widget> children;
  final PageDecorationLayoutBuilder? layoutBuilder;

  /// Presentation only: a host may suppress an old automatic cover. Storage
  /// ownership and request invalidation still use the actual view snapshot.
  final bool? hasCover;

  /// Null preserves the legacy showCoverAction gate. A read-only page may
  /// explicitly retain downloading without enabling any cover mutations.
  final bool? showDownloadAction;

  /// Tables suppress legacy automatic covers. Include their existing chosen
  /// marker in the SAME guarded save, never a second whole-extra write from
  /// an onViewChanged callback that can overwrite intervening settings.
  final bool markCoverChosen;
  final ViewCoverActionsBackend coverBackend;

  @override
  State<ViewDecorationActions> createState() => _ViewDecorationActionsState();
}

class _ViewDecorationActionsState extends State<ViewDecorationActions> {
  final coverPopoverController = PopoverController();
  bool coverPopoverOpen = false;
  bool iconPopoverOpen = false;
  VoidCallback? _releaseCover;
  int _coverGeneration = 0;
  late _CoverBinding _coverBinding;
  _CoverRequest? _coverRequest;

  _CoverBinding get _currentCoverBinding => (
        viewId: widget.view.id,
        locked: widget.view.isLocked,
        enabled: widget.showCoverAction,
        markChosen: widget.markCoverChosen,
        cover: widget.view.cover,
        backend: widget.coverBackend,
      );

  @override
  void initState() {
    super.initState();
    _coverBinding = _currentCoverBinding;
  }

  @override
  void didUpdateWidget(covariant ViewDecorationActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    final binding = _currentCoverBinding;
    final changedView = _coverBinding.viewId != binding.viewId;
    _coverRequest?.observedCovers.add(binding.cover);
    if (_coverBinding != binding) {
      _coverGeneration++;
      _coverBinding = binding;
      final release = _releaseCover;
      _releaseCover = null;
      final closeCover = coverPopoverOpen;
      coverPopoverOpen = false;
      if (closeCover) coverPopoverController.close();
      if (release != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => release());
      }
    }
    if (changedView || widget.view.isLocked || !widget.showIconAction) {
      iconPopoverOpen = false;
    }
  }

  @override
  void dispose() {
    _coverGeneration++;
    final release = _releaseCover;
    _releaseCover = null;
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
    super.dispose();
  }

  void _showCover(
    BuildContext actionContext,
    int generation,
    _CoverBinding binding,
  ) {
    if (!_canEditCover(generation, binding) ||
        _coverRequest != null ||
        coverPopoverOpen) {
      return;
    }
    _releaseCover = PreviewToolbarRegion.hold(actionContext);
    _setCoverPopoverOpen(true);
    coverPopoverController.show();
  }

  @override
  Widget build(BuildContext context) {
    // Menu/file-picker callbacks can outlive the widget that created them.
    final generation = _coverGeneration;
    final binding = _currentCoverBinding;
    final iconAction = widget.showIconAction && !widget.view.isLocked
        ? ViewIconPicker(
            key: const ValueKey('view-decoration-icon'),
            view: widget.view,
            onViewChanged: widget.onViewChanged,
            onOpenChanged: _setIconPopoverOpen,
            child: DecorationActionButton(
              icon: FlowySvgs.add_icon_s,
              label: widget.view.icon.value.isEmpty
                  ? LocaleKeys.document_plugins_cover_addIcon.tr()
                  : LocaleKeys.document_plugins_cover_changeIcon.tr(),
            ),
          )
        : null;
    final layoutBuilder = widget.layoutBuilder;
    final Widget toolbar;
    if (layoutBuilder == null) {
      final coverActions = _buildCoverActions(generation, binding);
      if (widget.leading == null &&
          widget.children.isEmpty &&
          iconAction == null &&
          coverActions.isEmpty) {
        return const SizedBox.shrink();
      }
      toolbar = WorkspaceActionRow(
        key: const ValueKey('view-decoration-actions-opacity'),
        leading: widget.leading,
        keepVisible: widget.visible || coverPopoverOpen || iconPopoverOpen,
        children: [
          ...widget.children,
          if (iconAction != null) iconAction,
          ...coverActions,
        ],
      );
    } else {
      toolbar = LayoutBuilder(
        builder: (context, constraints) {
          final coverActions = _buildCoverActions(
            generation,
            binding,
            compact: _hasCover &&
                (constraints.maxWidth < 480 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20),
          );
          final iconActions = [
            if (iconAction != null) iconAction,
            if (!_hasCover) ...coverActions,
          ];
          return layoutBuilder(
            iconActions.isEmpty
                ? null
                : PreviewToolbar(
                    key: const ValueKey('view-decoration-icon-actions'),
                    keepVisible: widget.visible ||
                        iconPopoverOpen ||
                        (!_hasCover && coverPopoverOpen),
                    child: Wrap(
                      spacing: WorkspaceTokens.space2,
                      runSpacing: WorkspaceTokens.space1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: iconActions,
                    ),
                  ),
            !_hasCover || coverActions.isEmpty
                ? null
                : Wrap(
                    key: const ValueKey('view-decoration-cover-actions'),
                    spacing: WorkspaceTokens.space1,
                    runSpacing: WorkspaceTokens.space1,
                    children: coverActions,
                  ),
            widget.children.isEmpty && widget.leading == null
                ? null
                : WorkspaceActionRow(
                    key: const ValueKey('view-decoration-actions-opacity'),
                    leading: widget.leading,
                    keepVisible: widget.visible,
                    children: widget.children,
                  ),
          );
        },
      );
    }
    // Standalone callers keep their old interaction boundary. Page headers
    // scope identity reveal separately from the image-local cover tools.
    return context.findAncestorWidgetOfExactType<PreviewToolbarRegion>() == null
        ? PreviewToolbarRegion(child: toolbar)
        : toolbar;
  }

  bool get _hasCover =>
      widget.hasCover ??
      (widget.view.cover != null && !widget.view.cover!.isNone);

  List<Widget> _buildCoverActions(
    int generation,
    _CoverBinding binding, {
    bool compact = false,
  }) =>
      [
        if (widget.showCoverAction && !widget.view.isLocked)
          AppFlowyPopover(
            key: const ValueKey('view-decoration-cover'),
            controller: coverPopoverController,
            triggerActions: PopoverTriggerFlags.none,
            direction: PopoverDirection.bottomWithLeftAligned,
            offset: const Offset(0, 8),
            margin: EdgeInsets.zero,
            constraints: const BoxConstraints(
              maxWidth: 540,
              maxHeight: 360,
              minHeight: 80,
            ),
            onClose: () => _setCoverPopoverOpen(false),
            child: Builder(
              builder: (actionContext) => DecorationActionButton(
                icon: FlowySvgs.add_cover_s,
                label: _hasCover
                    ? LocaleKeys.document_plugins_cover_changeCover.tr()
                    : LocaleKeys.document_plugins_cover_addCover.tr(),
                compact: compact,
                onTap: () => _showCover(actionContext, generation, binding),
              ),
            ),
            popupBuilder: (_) => UploadImageMenu(
              limitMaximumImageSize:
                  widget.userProfile?.workspaceType == WorkspaceTypePB.ServerW,
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
                await _selectCover(
                  generation,
                  binding,
                  localPath: files.first.path,
                );
              },
              onSelectedNetworkImage: (url) => _selectCover(
                generation,
                binding,
                cover: PageStyleCover(
                  type: PageStyleCoverImageType.unsplashImage,
                  value: url,
                ),
              ),
              onSelectedColor: (color) => _selectCover(
                generation,
                binding,
                cover: PageStyleCover(
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
        if ((widget.showDownloadAction ?? widget.showCoverAction) &&
            _hasCover &&
            _downloadableCover != null)
          DecorationActionButton(
            key: const ValueKey('view-decoration-download'),
            icon: FlowySvgs.download_s,
            label: LocaleKeys.document_plugins_cover_downloadCover.tr(),
            compact: compact,
            onTap: _downloadCover,
          ),
        if (widget.showCoverAction && !widget.view.isLocked && _hasCover)
          DecorationActionButton(
            key: const ValueKey('view-decoration-remove'),
            icon: FlowySvgs.delete_s,
            label: LocaleKeys.document_plugins_cover_removeCover.tr(),
            compact: compact,
            onTap: () => _selectCover(
              generation,
              binding,
              cover: const PageStyleCover.none(),
            ),
          ),
      ];

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
    if (!value) {
      _releaseCover?.call();
      _releaseCover = null;
    }
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

  bool _canEditCover(int generation, _CoverBinding binding) =>
      mounted &&
      generation == _coverGeneration &&
      binding == _currentCoverBinding &&
      binding.viewId.isNotEmpty &&
      binding.enabled &&
      !binding.locked;

  bool _isCurrent(_CoverRequest request) =>
      identical(_coverRequest, request) &&
      _canEditCover(request.generation, request.binding);

  Future<void> _selectCover(
    int generation,
    _CoverBinding binding, {
    String? localPath,
    PageStyleCover? cover,
  }) async {
    if (_coverRequest != null || !_canEditCover(generation, binding)) return;
    final request = _CoverRequest(
      generation: ++_coverGeneration,
      binding: binding,
      view: ViewPB.fromBuffer(widget.view.writeToBuffer())..freeze(),
      sourcePath: localPath,
      onViewChanged: widget.onViewChanged,
    );
    setState(() => _coverRequest = request);
    ViewCoverUpload? upload;
    try {
      if (coverPopoverOpen) coverPopoverController.close();
      if (localPath != null) {
        final profileResult = await request.binding.backend.currentUser();
        if (!_isCurrent(request)) return;
        final profile = profileResult.fold<UserProfilePB?>(
          (profile) => profile,
          (error) {
            showSnapBar(context, error.msg);
            return null;
          },
        );
        if (profile == null) return;
        upload = await request.binding.backend.upload(
          path: localPath,
          view: request.view,
          profile: profile,
        );
        if (!mounted || !_isCurrent(request)) return;
        cover = upload?.cover;
        if (cover == null || cover.value.isEmpty) {
          showSnapBar(
            context,
            LocaleKeys.document_plugins_image_imageUploadFailed.tr(),
          );
          return;
        }
      }
      if (cover != null && _isCurrent(request)) {
        await _saveCover(request, cover);
      }
    } catch (error) {
      Log.error('Unable to change view cover', error);
      if (mounted && _isCurrent(request)) {
        showSnapBar(context, 'Unable to change this cover. Try again.');
      }
    } finally {
      if (upload != null && !request.mayReferenceUpload) {
        await _discardUpload(request, upload);
      }
      // Keep the lock through cancellation/cleanup: a dispatched save cannot be
      // cancelled, and rebinding A -> B -> A must not start overlapping writes.
      _coverRequest = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveCover(_CoverRequest request, PageStyleCover cover) async {
    if (!_isCurrent(request)) return;
    // Keep the owning view immutable, but merge metadata delivered for that
    // same target while the profile/upload was pending.
    String extraForSave(String extra) =>
        request.binding.markChosen && !cover.isNone
            ? AutomaticViewCover.markCoverChosenByHand(extra)
            : extra;
    final view = request.view.rebuild(
      (view) => view.extra = extraForSave(widget.view.extra),
    );
    request.mayReferenceUpload = true;
    final result = await request.binding.backend.save(view: view, cover: cover);
    final saved = result.fold(
      (_) => true,
      (error) {
        request.mayReferenceUpload = false;
        if (_isCurrent(request)) showSnapBar(context, error.msg);
        return false;
      },
    );
    if (!saved || !_isCurrent(request)) return;

    // Do not freeze/mutate the host's protobuf or roll back newer names/icons.
    final updated = ViewPB.fromBuffer(widget.view.writeToBuffer())
      ..extra =
          ViewCoverCodec.mergeCover(extraForSave(widget.view.extra), cover);
    request.onViewChanged?.call(updated);
    // A callback may itself revoke access or change the authoritative target.
    if (!_isCurrent(request)) return;
    final previous = request.binding.cover;
    if (previous == null ||
        previous.isNone ||
        previous.value.isEmpty ||
        _referencesAsset(previous, cover.value) ||
        (request.sourcePath != null &&
            _referencesAsset(previous, request.sourcePath!))) {
      return;
    }
    // These are host-snapshot guards, not an atomic backend save/delete. Any
    // intervening cover update (even a matching save echo) skips old-asset GC.
    await _deleteAsset(request.binding.backend, previous);
  }

  Future<void> _discardUpload(
    _CoverRequest request,
    ViewCoverUpload upload,
  ) async {
    final cover = upload.cover;
    if (mounted) request.observedCovers.add(widget.view.cover);
    if (!upload.newlyCreated ||
        cover.value.isEmpty ||
        _referencesAsset(cover, request.sourcePath!) ||
        request.observedCovers.any(
          (known) => known != null && _referencesAsset(cover, known.value),
        )) {
      return;
    }
    await _deleteAsset(request.binding.backend, cover);
  }

  Future<void> _deleteAsset(
    ViewCoverActionsBackend backend,
    PageStyleCover cover,
  ) async {
    if (!cover.isLocalImage && !cover.isCustomImage) return;
    try {
      await backend.delete(cover);
    } catch (error) {
      // Cleanup failure must not turn an already successful save into failure.
      Log.error('Unable to clean up cover asset', error);
    }
  }
}

typedef _CoverBinding = ({
  String viewId,
  bool locked,
  bool enabled,
  bool markChosen,
  PageStyleCover? cover,
  ViewCoverActionsBackend backend,
});

class _CoverRequest {
  _CoverRequest({
    required this.generation,
    required this.binding,
    required this.view,
    required this.sourcePath,
    required this.onViewChanged,
  }) : observedCovers = {binding.cover};

  final int generation;
  final _CoverBinding binding;
  final ViewPB view;
  final String? sourcePath;
  final ValueChanged<ViewPB>? onViewChanged;
  final Set<PageStyleCover?> observedCovers;

  // Success, stale success and thrown/unknown save outcomes retain the upload.
  bool mayReferenceUpload = false;
}

bool _referencesAsset(PageStyleCover cover, String value) {
  if (cover.value == value) return true;
  if (!cover.isLocalImage) return false;
  String localPath(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null || uri.scheme != 'file') return source;
    return uri.toFilePath(
      windows: uri.host.isNotEmpty || RegExp('^/[A-Za-z]:/').hasMatch(uri.path),
    );
  }

  try {
    final assetPath = localPath(cover.value);
    // Compare persisted Windows paths as Windows paths even in an offline test
    // running on another platform (including file-URI and case aliases).
    final paths = RegExp(r'^[A-Za-z]:[\\/]|^\\\\').hasMatch(assetPath)
        ? p.windows
        : p.context;
    return paths.equals(assetPath, localPath(value));
  } catch (_) {
    // An unresolvable local reference is not proof that deletion is safe.
    return true;
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
    this.updateIcon = ViewBackendService.updateViewIcon,
  });

  final ViewPB view;
  final Widget child;
  final ValueChanged<ViewPB>? onViewChanged;
  final ValueChanged<bool>? onOpenChanged;
  final PopoverDirection direction;
  final Future<FlowyResult<void, FlowyError>> Function({
    required ViewPB view,
    required EmojiIconData viewIcon,
  }) updateIcon;

  @override
  State<ViewIconPicker> createState() => _ViewIconPickerState();
}

class _ViewIconPickerState extends State<ViewIconPicker> {
  final controller = PopoverController();
  int _generation = 0;
  bool _saving = false;
  VoidCallback? _releasePreview;

  void _show() {
    if (widget.view.isLocked || _releasePreview != null) return;
    _releasePreview = PreviewToolbarRegion.hold(context);
    widget.onOpenChanged?.call(true);
    controller.show();
  }

  void _release() {
    _releasePreview?.call();
    _releasePreview = null;
  }

  @override
  void dispose() {
    _generation++;
    final release = _releasePreview;
    _releasePreview = null;
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ViewIconPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id ||
        oldWidget.view.isLocked != widget.view.isLocked ||
        oldWidget.updateIcon != widget.updateIcon) {
      final release = _releasePreview;
      _releasePreview = null;
      _generation++;
      controller.close();
      if (release != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => release());
      }
    }
  }

  bool _canSelect(int generation, String viewId) =>
      mounted &&
      generation == _generation &&
      viewId == widget.view.id &&
      !widget.view.isLocked;

  Future<void> _select(
    SelectedEmojiIconResult result,
    int generation,
    String viewId,
  ) async {
    if (!_canSelect(generation, viewId) || _saving) return;
    _saving = true;
    try {
      final update = await widget.updateIcon(
        view: widget.view,
        viewIcon: result.data,
      );
      if (!_canSelect(generation, viewId)) return;
      update.fold(
        (_) {
          final updated = ViewPB.fromBuffer(widget.view.writeToBuffer())
            ..icon = result.data.toViewIcon();
          widget.onViewChanged?.call(updated);
          if (!result.keepOpen) controller.close();
        },
        (error) => showSnapBar(context, error.msg),
      );
    } catch (_) {
      if (mounted && _canSelect(generation, viewId)) {
        showSnapBar(context, 'Unable to change this icon. Try again.');
      }
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.view.isLocked) {
      return ExcludeFocus(child: IgnorePointer(child: widget.child));
    }
    final tooltip = widget.view.icon.value.isEmpty
        ? LocaleKeys.document_plugins_cover_addIcon.tr()
        : LocaleKeys.document_plugins_cover_changeIcon.tr();
    return AppFlowyPopover(
      controller: controller,
      direction: widget.direction,
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      constraints: BoxConstraints.loose(const Size(360, 380)),
      triggerActions: PopoverTriggerFlags.none,
      onClose: () {
        _generation++;
        _release();
        widget.onOpenChanged?.call(false);
      },
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: TextButton(
          onPressed: _show,
          style: WorkspaceChrome.controlStyle(context).copyWith(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: const WidgetStatePropertyAll(Size.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Semantics(
            label: tooltip,
            child: ExcludeSemantics(child: widget.child),
          ),
        ),
      ),
      popupBuilder: (_) {
        final generation = _generation;
        final viewId = widget.view.id;
        return FlowyIconEmojiPicker(
          documentId: viewId,
          initialType: widget.view.icon.toEmojiIconData().toPickerTabType(),
          tabs: kAllIconPickerTabs,
          onSelectedEmoji: (result) => _select(result, generation, viewId),
        );
      },
    );
  }
}

/// Only colorful saved artwork opts into the larger identity frame. Default
/// outline glyphs and monochrome library choices retain their requested size.
/// This is presentation metadata only; no packs or profile data are loaded.
bool isColorfulViewIcon(EmojiIconData icon) {
  if (icon.isEmpty) return false;
  if (icon.type != FlowyIconType.icon) return true;
  try {
    final data = IconsData.fromJson(jsonDecode(icon.emoji));
    return iconPackForGroup(data.groupName).isColorful;
  } catch (_) {
    // The icon renderer retains responsibility for malformed saved values.
    return false;
  }
}

class DecorationActionButton extends StatelessWidget {
  const DecorationActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.compact = false,
  });

  final FlowySvgData icon;
  final String label;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkspaceGlyph.svg(
          icon,
          size: 16,
          color: palette.secondaryText,
        ),
        if (!compact) const SizedBox(width: 6),
        if (!compact)
          Flexible(
            child: Text(
              label,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.body,
                color: palette.secondaryText,
              ),
            ),
          ),
      ],
    );
    final style = WorkspaceChrome.controlStyle(context).copyWith(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      ),
    );
    final buttonContent = compact
        ? Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Semantics(
              label: label,
              child: ExcludeSemantics(child: content),
            ),
          )
        : content;
    // ViewIconPicker already owns a native button. Older workspace-cover
    // popovers own only a pointer listener, so give those a keyboard trigger
    // too without changing their persistence or opening a second popup.
    if (onTap == null) {
      if (context.findAncestorWidgetOfExactType<TextButton>() != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: content,
        );
      }
      return _PopoverDecorationAction(style: style, child: buttonContent);
    }
    return TextButton(
      onPressed: onTap,
      style: style,
      child: buttonContent,
    );
  }
}

class _PopoverDecorationAction extends StatefulWidget {
  const _PopoverDecorationAction({required this.style, required this.child});

  final ButtonStyle style;
  final Widget child;

  @override
  State<_PopoverDecorationAction> createState() =>
      _PopoverDecorationActionState();
}

class _PopoverDecorationActionState extends State<_PopoverDecorationAction> {
  PopoverState? _popover;
  VoidCallback? _releasePreview;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_releaseIfClosed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _popover = context.findAncestorStateOfType<PopoverState>();
  }

  void _hold() {
    _releasePreview ??= PreviewToolbarRegion.hold(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _releaseIfClosed());
  }

  void _releaseIfClosed() {
    final popover = _popover;
    if (popover == null || !PopoverState.rootEntry.contains(popover)) {
      _releasePreview?.call();
      _releasePreview = null;
    }
  }

  void _show() {
    final popover = _popover;
    if (popover == null) return;
    _hold();
    if (!PopoverState.rootEntry.contains(popover)) {
      popover.widget.onOpen?.call();
      popover.showOverlay();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_releaseIfClosed);
    final release = _releasePreview;
    _releasePreview = null;
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _hold(),
        child: TextButton(
          onPressed: _popover == null ? null : _show,
          style: widget.style,
          child: widget.child,
        ),
      );
}
