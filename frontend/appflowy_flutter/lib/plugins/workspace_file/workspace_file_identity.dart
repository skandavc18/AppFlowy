import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_icon_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/document_viewer/file_action_band.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/page_icon.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

typedef WorkspaceFileIconWriter = Future<FlowyResult<void, FlowyError>>
    Function({
  required ViewPB view,
  required EmojiIconData viewIcon,
});

/// One retained identity row for a workspace file, independent of its renderer.
/// Rename changes the workspace view only; the repository never sees a file.
class WorkspaceFileIdentityRow extends StatefulWidget {
  const WorkspaceFileIdentityRow({
    super.key,
    required this.view,
    required this.binding,
    required this.summary,
    required this.canRename,
    required this.onViewChanged,
    required this.repository,
    required this.source,
    required this.mediaActions,
    required this.fileAvailable,
    required this.actionsVisible,
    this.controls = const StandaloneFileHeader(),
    this.coverBackend = const ViewCoverActionsBackend(),
    this.updateIcon = ViewBackendService.updateViewIcon,
    this.userProfile,
  });

  final ViewPB view;
  final Object binding;
  final String summary;
  final bool Function() canRename;
  final ValueChanged<ViewPB> onViewChanged;
  final WorkspaceItemRepository repository;
  final MediaActionSource source;
  final MediaActionService mediaActions;
  final bool fileAvailable;
  final bool actionsVisible;
  final StandaloneFileHeader controls;
  final ViewCoverActionsBackend coverBackend;
  final WorkspaceFileIconWriter updateIcon;
  final UserProfilePB? userProfile;

  @override
  State<WorkspaceFileIdentityRow> createState() =>
      _WorkspaceFileIdentityRowState();
}

class _WorkspaceFileIdentityRowState extends State<WorkspaceFileIdentityRow> {
  final _titleFocus = FocusNode(debugLabel: 'workspace-file-title');
  final _toolsScroll = ScrollController();
  // A renderer publishes after loading. Moving the original-file actions into
  // its toolbar must not reset a pending Copy/Share or its focus/feedback.
  final _fileActionsKey = GlobalKey(debugLabel: 'workspace-file-actions');
  bool _renaming = false;
  bool _saving = false;
  bool _pickerOpen = false;
  bool _headerActive = false;
  bool _failed = false;
  bool? _wasEditable;
  int _generation = 0;

  bool get _canRename => mounted && widget.canRename();
  String get _name => widget.view.name.isEmpty
      ? LocaleKeys.workspaceFolderExplorer_untitledFile.tr()
      : widget.view.name;

  void _setHeaderActive(bool value) {
    if (mounted && _headerActive != value) {
      setState(() => _headerActive = value);
    }
  }

  @override
  void didUpdateWidget(covariant WorkspaceFileIdentityRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id ||
        oldWidget.binding != widget.binding ||
        oldWidget.repository != widget.repository ||
        oldWidget.updateIcon != widget.updateIcon) {
      _generation++;
      _renaming = false;
      _pickerOpen = false;
      _failed = false;
      // An already-dispatched write cannot be cancelled. Keep its lock even
      // when A -> B -> A is visited before the backend answers.
    }
    if (_wasEditable == true && !_canRename) {
      _generation++;
      _pickerOpen = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _titleFocus.dispose();
    _toolsScroll.dispose();
    super.dispose();
  }

  void _beginRename() {
    if (!_canRename || _renaming || _saving) return;
    setState(() {
      _generation++;
      _renaming = true;
      _failed = false;
    });
  }

  void _cancelRename() {
    setState(() {
      _generation++;
      _renaming = false;
      _failed = false;
    });
    _titleFocus.requestFocus();
  }

  bool _current(int generation, Object binding, String id) =>
      _canRename &&
      _renaming &&
      generation == _generation &&
      binding == widget.binding &&
      id == widget.view.id;

  Future<bool> _rename(
    String value,
    int generation,
    Object binding,
    String id,
  ) async {
    if (_saving || !_current(generation, binding, id)) return false;
    final original = widget.view;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    // Selecting the stem keeps the extension. Typing a replacement name with
    // no suffix does too; an explicitly supplied extension is left intact.
    final name = p.extension(trimmed).isEmpty
        ? '$trimmed${p.extension(original.name)}'
        : trimmed;
    if (name == original.name) {
      setState(() => _renaming = false);
      return true;
    }
    final repository = widget.repository;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      // Read the real view before dispatch: a cached unlocked title is not
      // authority to rename a locked, deleted or replaced workspace item.
      final read = await repository.getView(id);
      if (!_current(generation, binding, id)) return false;
      final live = read.fold<ViewPB?>((view) => view, (_) => null);
      if (live == null ||
          live.id != id ||
          live.isLocked ||
          widget.view.name != original.name ||
          live.name != original.name ||
          live.workspaceItem?.storageUrl !=
              original.workspaceItem?.storageUrl) {
        setState(() => _failed = true);
        return false;
      }
      final result = await repository.rename(viewId: id, name: name);
      if (!_current(generation, binding, id)) return false;
      final saved = result.fold(
        // UpdateView may return an empty success ACK, not a populated ViewPB.
        (view) => view.id.isEmpty || view.id == id,
        (_) => false,
      );
      if (!saved ||
          (widget.view.name != original.name && widget.view.name != name)) {
        setState(() => _failed = true);
        return false;
      }
      final updated = ViewPB.fromBuffer(widget.view.writeToBuffer())
        ..name = name;
      widget.onViewChanged(updated);
      if (!mounted || generation != _generation) return false;
      setState(() => _renaming = false);
      return true;
    } catch (_) {
      // Keep the editor's draft. Backend details can contain local paths;
      // report the existing localized failure instead of echoing the error.
      if (_current(generation, binding, id)) {
        setState(() => _failed = true);
      }
      return false;
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  Future<FlowyResult<void, FlowyError>> _writeIcon({
    required ViewPB view,
    required EmojiIconData viewIcon,
  }) async {
    final generation = _generation;
    final binding = widget.binding;
    final repository = widget.repository;
    final update = widget.updateIcon;
    bool current() =>
        _canRename &&
        generation == _generation &&
        binding == widget.binding &&
        view.id == widget.view.id &&
        update == widget.updateIcon;
    FlowyResult<void, FlowyError> refused() => FlowyResult.failure(
          FlowyError(msg: 'This file is no longer available for editing.'),
        );
    if (!current()) return refused();
    final read = await repository.getView(view.id);
    final live = read.fold<ViewPB?>((view) => view, (_) => null);
    if (!current() ||
        live == null ||
        live.id != view.id ||
        live.isLocked ||
        live.workspaceItem?.storageUrl != view.workspaceItem?.storageUrl) {
      return refused();
    }
    return update(view: live, viewIcon: viewIcon);
  }

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    final canRename = _canRename;
    _wasEditable = canRename;
    final generation = _generation;
    final binding = widget.binding;
    final id = widget.view.id;
    final glyph = SizedBox.square(
      dimension: WorkspaceTokens.pageIconSize,
      child: Center(
        child: FileIdentityGlyph(
          icon: widget.view.icon.toEmojiIconData(),
          name: _name,
          size: WorkspaceTokens.pageIconSize,
          color: style.icon,
        ),
      ),
    );
    final fileActions = Wrap(
      key: _fileActionsKey,
      spacing: WorkspaceTokens.space1,
      runSpacing: WorkspaceTokens.space1,
      alignment: fileActionRunAlignment(context),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...widget.controls.actions,
        ExcludeFocus(
          excluding: !widget.fileAvailable,
          child: Visibility(
            visible: widget.fileAvailable,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: MediaActionButtons(
              source: widget.source,
              actions: widget.mediaActions,
              decorated: false,
            ),
          ),
        ),
        if (canRename)
          WorkspaceControlButton(
            key: const ValueKey('workspace-file-rename'),
            icon: Icons.drive_file_rename_outline_rounded,
            tooltip: LocaleKeys.disclosureAction_rename.tr(),
            onPressed: _saving ? null : _beginRename,
          ),
      ],
    );
    final toolbarBuilder = widget.controls.toolbarBuilder;
    final toolbar = toolbarBuilder == null
        ? Wrap(
            spacing: WorkspaceTokens.space2,
            runSpacing: WorkspaceTokens.space1,
            alignment: fileActionRunAlignment(context),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.controls.toolbar != null) widget.controls.toolbar!,
              fileActions,
            ],
          )
        : Builder(builder: (context) => toolbarBuilder(context, fileActions));
    final coverView = widget.view;
    final cover = coverView.cover;
    Widget iconPicker(Widget child, String role) => ViewIconPicker(
          key: ValueKey((role, binding, widget.repository, widget.updateIcon)),
          view: widget.view,
          updateIcon: _writeIcon,
          onViewChanged: (view) {
            if (_canRename &&
                generation == _generation &&
                binding == widget.binding &&
                id == widget.view.id &&
                view.id == id) {
              // An icon write must not roll back a concurrent title/cover edit.
              widget.onViewChanged(
                ViewPB.fromBuffer(widget.view.writeToBuffer())
                  ..icon = view.icon,
              );
            }
          },
          onOpenChanged: (value) {
            if (mounted && binding == widget.binding) {
              setState(() => _pickerOpen = value);
            }
          },
          child: child,
        );

    Widget header(Widget? coverAction) => LayoutBuilder(
          builder: (context, constraints) {
            final inset = WorkspaceTokens.pageInset(constraints.maxWidth);
            // Copy's badge sits above the controls, inside the band's clip.
            final feedback =
                MediaQuery.textScalerOf(context).scale(10) * 1.2 + 10;
            return DocumentViewportBar(
              key: const ValueKey('workspace-file-identity-row'),
              background: style.canvas,
              padding: EdgeInsets.fromLTRB(
                inset,
                cover == null || cover.isNone
                    ? WorkspaceTokens.pageTopWithoutCover
                    : WorkspaceTokens.pageTopWithCover,
                inset,
                WorkspaceTokens.pageHeaderBottom,
              ),
              child: WorkspacePageIdentity(
                icon: KeyedSubtree(
                  key: const ValueKey('workspace-file-identity-icon'),
                  child: ResizablePageIcon(
                    view: widget.view,
                    binding: (
                      widget.binding,
                      widget.repository,
                      widget.view.workspaceItem?.storageUrl,
                    ),
                    editable: canRename,
                    canResize: () =>
                        _canRename &&
                        binding == widget.binding &&
                        id == widget.view.id,
                    isSameTarget: (fresh) =>
                        fresh.workspaceItem != null &&
                        fresh.workspaceItem?.storageUrl ==
                            widget.view.workspaceItem?.storageUrl &&
                        fresh.workspaceItem?.contentKind ==
                            widget.view.workspaceItem?.contentKind,
                    onSizeChanged: (size) {
                      if (_canRename &&
                          binding == widget.binding &&
                          id == widget.view.id) {
                        widget
                            .onViewChanged(IconSize.applyTo(widget.view, size));
                      }
                    },
                    builder: (size, _) => canRename
                        ? iconPicker(
                            PageIconArtwork(size: size, child: glyph),
                            'glyph',
                          )
                        : PageIconArtwork(size: size, child: glyph),
                  ),
                ),
                iconActions: canRename
                    ? PreviewToolbarRegion(
                        child: PreviewToolbar(
                          keepVisible: _headerActive || _pickerOpen,
                          child: Wrap(
                            spacing: WorkspaceTokens.space2,
                            runSpacing: WorkspaceTokens.space1,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              KeyedSubtree(
                                key: const ValueKey(
                                  'workspace-file-change-icon',
                                ),
                                child: iconPicker(
                                  DecorationActionButton(
                                    icon: FlowySvgs.add_icon_s,
                                    label: LocaleKeys
                                        .document_plugins_cover_changeIcon
                                        .tr(),
                                  ),
                                  'change-icon',
                                ),
                              ),
                              if (coverAction != null)
                                KeyedSubtree(
                                  key: const ValueKey(
                                    'workspace-file-add-cover',
                                  ),
                                  child: coverAction,
                                ),
                            ],
                          ),
                        ),
                      )
                    : null,
                title: Focus(
                  focusNode: _titleFocus,
                  canRequestFocus: canRename,
                  skipTraversal: !canRename,
                  onKeyEvent: (_, event) {
                    if (!_renaming &&
                        canRename &&
                        event is KeyDownEvent &&
                        (isWorkspaceRenameShortcut(
                              Theme.of(context).platform,
                              event.logicalKey,
                            ) ||
                            event.logicalKey == LogicalKeyboardKey.enter)) {
                      _beginRename();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Listener(
                    onPointerDown: (_) {
                      if (!_renaming) _titleFocus.requestFocus();
                    },
                    child: Tooltip(
                      message: _name,
                      excludeFromSemantics: true,
                      child: ExcludeFocus(
                        excluding: !canRename,
                        child: IgnorePointer(
                          ignoring: !canRename,
                          child: TextEntryShortcuts(
                            child: WorkspaceInlineEditableText(
                              key: const ValueKey('workspace-file-name'),
                              text: _name,
                              editing: _renaming,
                              selectFileStem: true,
                              maxLines: 2,
                              style: WorkspaceTypography.style(
                                context,
                                WorkspaceTextRole.pageTitle,
                                compact: constraints.maxWidth < 600,
                              ),
                              onDoubleTap: canRename ? _beginRename : null,
                              onSubmitted: (name) =>
                                  _rename(name, generation, binding, id),
                              onCancelled: () {
                                if (mounted &&
                                    generation == _generation &&
                                    binding == widget.binding) {
                                  _cancelRename();
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                metadata: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.summary,
                      key: const ValueKey('workspace-file-metadata'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_failed)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          LocaleKeys.workspaceFolderExplorer_operationFailed
                              .tr(),
                          key: const ValueKey('workspace-file-rename-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
                metadataSpacing: WorkspaceTokens.space1,
                trailingTopInset: feedback,
                trailing: PreviewToolbar(
                  key: const ValueKey('workspace-file-tools'),
                  // Standalone file tools are persistent, unlike inline
                  // editing overlays. Keep the retained subtree and clipping.
                  keepVisible: true,
                  child: FileActionBand(
                    scrollKey: const ValueKey('workspace-file-toolbar-scroll'),
                    controller: _toolsScroll,
                    hug: true,
                    responsive: toolbarBuilder == null ||
                        widget.controls.responsiveToolbar,
                    padding: EdgeInsets.only(top: feedback),
                    builder: (context) => ConstrainedBox(
                      // The band hugs its controls and clips; keep room for
                      // Copy's badge when the toolbar is shorter than it.
                      constraints: const BoxConstraints(
                        minWidth: mediaActionFeedbackExtent,
                      ),
                      child: Column(
                        key: const ValueKey('workspace-file-toolbar-content'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (widget.controls.leading != null)
                            widget.controls.leading!,
                          toolbar,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
    final decoration = ViewDecorationActions(
      key: const ValueKey('workspace-file-decoration'),
      view: widget.view,
      userProfile: widget.userProfile,
      coverBackend: widget.coverBackend,
      showIconAction: false,
      showCoverAction: canRename,
      visible: _headerActive || _pickerOpen,
      onViewChanged: (updated) {
        if (!_canRename ||
            binding != widget.binding ||
            id != widget.view.id ||
            updated.id != id) {
          return;
        }
        // The cover model owns the write. Merge only its cover into the live
        // host view; never dispatch a second raw-extra write or undo a rename.
        widget.onViewChanged(
          ViewPB.fromBuffer(widget.view.writeToBuffer())
            ..extra = ViewCoverCodec.mergeCover(
              widget.view.extra,
              updated.cover ?? const PageStyleCover.none(),
            ),
        );
      },
      layoutBuilder: (iconActions, coverActions, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cover != null && !cover.isNone)
            Padding(
              key: const ValueKey('workspace-file-cover'),
              padding: const EdgeInsets.all(WorkspaceTokens.coverInset),
              child: LayoutBuilder(
                builder: (context, constraints) => PageCoverLayout(
                  width: constraints.maxWidth,
                  fallbackHeight: (MediaQuery.sizeOf(context).height * 0.18)
                      .clamp(96.0, WorkspaceTokens.compactCoverHeight)
                      .toDouble(),
                  view: coverView,
                  binding: (
                    binding,
                    widget.repository,
                    coverView.workspaceItem?.storageUrl,
                  ),
                  editable: canRename && !_saving,
                  // Copy/Share owns its private pending lock independently;
                  // changing cover geometry does not replace that action owner.
                  canResize: () =>
                      _canRename &&
                      !_saving &&
                      binding == widget.binding &&
                      samePageCoverSource(coverView, widget.view),
                  isSameTarget: (fresh) =>
                      fresh.workspaceItem != null &&
                      fresh.workspaceItem?.storageUrl ==
                          coverView.workspaceItem?.storageUrl &&
                      fresh.workspaceItem?.contentKind ==
                          coverView.workspaceItem?.contentKind,
                  onHeightChanged: (height) {
                    if (_canRename &&
                        !_saving &&
                        binding == widget.binding &&
                        samePageCoverSource(coverView, widget.view)) {
                      widget.onViewChanged(
                        PageCoverHeight.applyTo(widget.view, height),
                      );
                    }
                  },
                  builder: (context, height, grip) => SizedBox(
                    height: height,
                    child: WorkspacePageCover(
                      image: ViewCoverImage(
                        cover: cover,
                        userProfile: widget.userProfile,
                      ),
                      actions: coverActions,
                      resizeGrip: grip,
                    ),
                  ),
                ),
              ),
            ),
          // Keep the heading keyed when a cover appears/disappears:
          // title drafts, media actions and the renderer below stay mounted.
          KeyedSubtree(
            key: const ValueKey('workspace-file-heading'),
            child: header(iconActions),
          ),
        ],
      ),
    );
    // Scope only decorations locally: file tools must still inherit viewer
    // hover and holds from renderer-owned menus. Forward header interaction
    // without shadowing that scope or moving the retained media actions.
    return MouseRegion(
      key: const ValueKey('workspace-file-header-region'),
      opaque: false,
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: (_) => _setHeaderActive(true),
      onHover: (_) => _setHeaderActive(true),
      onExit: (_) => _setHeaderActive(false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.touch ||
              event.kind == PointerDeviceKind.stylus ||
              event.kind == PointerDeviceKind.invertedStylus) {
            _setHeaderActive(true);
          }
        },
        child: decoration,
      ),
    );
  }
}
