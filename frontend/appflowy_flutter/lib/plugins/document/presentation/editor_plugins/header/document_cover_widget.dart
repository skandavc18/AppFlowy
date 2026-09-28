import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/plugins/base/emoji/emoji_picker_screen.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/desktop_cover.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/migration/editor_migration.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/page_icon.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_layout.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/cover_image_download.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide UploadImageMenu;
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/rounded_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';

import 'cover_title.dart';

const double kCoverHeight = 280.0;
const double kDesktopCoverHeight = WorkspaceTokens.coverHeight;
const double kTitleIconSize = WorkspaceTokens.pageIconSize;
const double kToolbarHeight = 40.0; // with padding to the top

/// The title shares the body's reading edges, but does not contain its
/// leading block-action row. Changing constraints only relays out this frame;
/// the title's focus and draft stay at the same element-tree depth.
class DocumentHeaderContent extends StatelessWidget {
  const DocumentHeaderContent({
    super.key,
    required this.editorStyle,
    required this.child,
    this.includeVerticalPadding = true,
  });

  final EditorStyle editorStyle;
  final Widget child;
  final bool includeVerticalPadding;

  @override
  Widget build(BuildContext context) {
    final padding = EditorStyleCustomizer.documentHeaderPadding(
      editorStyle.padding,
      textDirection: Directionality.of(context),
    );
    return Center(
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxWidth: editorStyle.maxWidth ?? double.infinity,
        ),
        padding: includeVerticalPadding
            ? padding
            : EdgeInsets.only(left: padding.left, right: padding.right),
        child: child,
      ),
    );
  }
}

/// The picture belongs to the page, not its text measure. Only identity uses
/// the saved editor width and its exact (including RTL) block-action insets.
/// Keyed identity/title slots retain drafts while cover/icon tools come and go.
class DocumentHeaderLayout extends StatelessWidget {
  const DocumentHeaderLayout({
    super.key,
    required this.editorStyle,
    required this.title,
    this.icon,
    this.iconActions,
    this.cover,
    this.coverActions,
    this.actions,
    this.coverView,
    this.coverBinding,
    this.coverEditable = false,
    this.canResizeCover,
    this.onCoverHeightChanged,
  });

  final EditorStyle editorStyle;
  final Widget title;
  final Widget? icon;
  final Widget? iconActions;
  final Widget? cover;
  final Widget? coverActions;
  final Widget? actions;
  final ViewPB? coverView;
  final Object? coverBinding;
  final bool coverEditable;
  final bool Function()? canResizeCover;
  final ValueChanged<double?>? onCoverHeightChanged;

  @override
  Widget build(BuildContext context) {
    final padding = EditorStyleCustomizer.documentHeaderPadding(
      editorStyle.padding,
      textDirection: Directionality.of(context),
    );
    return WorkspacePageHeader(
      maxWidth: editorStyle.maxWidth ?? double.infinity,
      contentInset: 0,
      cover: cover,
      coverActions: coverActions,
      coverView: coverView,
      coverBinding: coverBinding,
      coverEditable: coverEditable,
      canResizeCover: canResizeCover,
      onCoverHeightChanged: onCoverHeightChanged,
      overlapIcon: icon != null,
      identity: Padding(
        key: const ValueKey('document-page-identity'),
        padding: EdgeInsets.only(left: padding.left, right: padding.right),
        child: WorkspacePageIdentity(
          icon: icon == null
              ? null
              : SizedBox(
                  key: const ValueKey('document-page-icon-slot'),
                  child: icon,
                ),
          iconActions: iconActions,
          title: title,
          actions: actions,
        ),
      ),
    );
  }
}

// Remove this widget if the desktop support immersive cover.
class DocumentHeaderBlockKeys {
  const DocumentHeaderBlockKeys._();

  static const String coverType = 'cover_selection_type';
  static const String coverDetails = 'cover_selection';
  static const String icon = 'selected_icon';
}

// for the version under 0.5.5, including 0.5.5
enum CoverType {
  none,
  color,
  file,
  asset;

  static CoverType fromString(String? value) {
    if (value == null) {
      return CoverType.none;
    }
    return CoverType.values.firstWhere(
      (e) => e.toString() == value,
      orElse: () => CoverType.none,
    );
  }
}

// This key is used to intercept the selection event in the document cover widget.
const _interceptorKey = 'document_cover_widget_interceptor';

class DocumentCoverWidget extends StatefulWidget {
  const DocumentCoverWidget({
    super.key,
    required this.node,
    required this.editorState,
    required this.onIconChanged,
    required this.view,
    required this.tabs,
    this.titleBuilder,
    this.viewListenerFactory,
  });

  final Node node;
  final EditorState editorState;
  final ValueChanged<EmojiIconData> onIconChanged;
  final ViewPB view;
  final List<PickerTabType> tabs;

  /// Optional host boundaries; defaults retain the native title and listener.
  final Widget Function(ViewPB view)? titleBuilder;
  final ViewListener Function(String viewId)? viewListenerFactory;

  @override
  State<DocumentCoverWidget> createState() => _DocumentCoverWidgetState();
}

class _DocumentCoverWidgetState extends State<DocumentCoverWidget> {
  CoverType get coverType => CoverType.fromString(
        widget.node.attributes[DocumentHeaderBlockKeys.coverType],
      );

  String? get coverDetails =>
      widget.node.attributes[DocumentHeaderBlockKeys.coverDetails];

  String? get icon => widget.node.attributes[DocumentHeaderBlockKeys.icon];

  bool get hasIcon => viewIcon.emoji.isNotEmpty;

  // Match DesktopCover's V1/V2 source selection. An explicit modern removal
  // wins over an old node attribute; do not keep a blank hero in its place.
  bool get hasCover => view.cover == null
      ? coverType != CoverType.none
      : cover != null && cover?.type != PageStyleCoverImageType.none;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  EmojiIconData viewIcon = EmojiIconData.none();

  PageStyleCover? cover;
  late ViewPB view;
  late ViewListener viewListener;
  int _viewListenerGeneration = 0;

  final isCoverTitleHovered = ValueNotifier<bool>(false);

  late final gestureInterceptor = SelectionGestureInterceptor(
    key: _interceptorKey,
    canTap: (details) => !_isTapInBounds(details.globalPosition),
    canPanStart: (details) => !_isDragInBounds(details.globalPosition),
  );

  @override
  void initState() {
    super.initState();
    final icon = widget.view.icon;
    viewIcon = EmojiIconData.fromViewIconPB(icon);
    cover = widget.view.cover;
    view = widget.view;
    widget.node.addListener(_reload);
    widget.editorState.service.selectionService
        .registerGestureInterceptor(gestureInterceptor);
    _bindViewListener();
  }

  void _bindViewListener() {
    final generation = ++_viewListenerGeneration;
    final viewId = widget.view.id;
    viewListener = (widget.viewListenerFactory?.call(widget.view.id) ??
        ViewListener(viewId: widget.view.id))
      ..start(
        onViewUpdated: (updated) {
          if (!mounted ||
              generation != _viewListenerGeneration ||
              updated.id != viewId ||
              widget.view.id != viewId) return;
          setState(() {
            viewIcon = EmojiIconData.fromViewIconPB(updated.icon);
            cover = updated.cover;
            view = updated;
          });
        },
      );
  }

  @override
  void didUpdateWidget(covariant DocumentCoverWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      oldWidget.node.removeListener(_reload);
      widget.node.addListener(_reload);
    }
    if (oldWidget.editorState != widget.editorState) {
      oldWidget.editorState.service.selectionService
          .unregisterGestureInterceptor(_interceptorKey);
      widget.editorState.service.selectionService
          .registerGestureInterceptor(gestureInterceptor);
    }
    if (oldWidget.view.id != widget.view.id ||
        oldWidget.viewListenerFactory != widget.viewListenerFactory) {
      unawaited(viewListener.stop());
      _bindViewListener();
    }
    if (oldWidget.view != widget.view) {
      view = widget.view;
      viewIcon = EmojiIconData.fromViewIconPB(view.icon);
      cover = view.cover;
    }
  }

  @override
  void dispose() {
    _viewListenerGeneration++;
    unawaited(viewListener.stop());
    widget.node.removeListener(_reload);
    isCoverTitleHovered.dispose();
    widget.editorState.service.selectionService
        .unregisterGestureInterceptor(_interceptorKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (UniversalPlatform.isDesktopOrWeb) {
      return PreviewToolbarRegion(
        child: DocumentCover(
          view: view,
          editorState: widget.editorState,
          node: widget.node,
          coverType: coverType,
          coverDetails: coverDetails,
          showCoverActions: hasCover,
          onChangeCover: (type, details) =>
              _saveIconOrCover(cover: (type, details)),
          layoutBuilder: (image, coverActions) => DocumentHeaderLayout(
            editorStyle: widget.editorState.editorStyle,
            coverView: view,
            coverBinding: (
              widget.editorState,
              widget.node,
              coverType,
              coverDetails
            ),
            coverEditable: widget.editorState.editable,
            canResizeCover: () =>
                mounted && widget.editorState.editable && hasCover,
            onCoverHeightChanged: (height) {
              if (mounted && widget.editorState.editable) {
                setState(() => view = PageCoverHeight.applyTo(view, height));
              }
            },
            cover: hasCover ? image : null,
            coverActions: coverActions.isEmpty
                ? null
                : Wrap(
                    spacing: WorkspaceTokens.space1,
                    runSpacing: WorkspaceTokens.space1,
                    children: coverActions,
                  ),
            icon: hasIcon ? _buildResizableIcon(optical: true) : null,
            title: ExcludeFocus(
              excluding: !widget.editorState.editable,
              child: IgnorePointer(
                ignoring: !widget.editorState.editable,
                child: widget.titleBuilder?.call(widget.view) ??
                    CoverTitle(
                      key: const ValueKey('document-cover-title'),
                      view: widget.view,
                    ),
              ),
            ),
            iconActions: widget.editorState.editable
                ? PreviewToolbar(
                    key: const ValueKey('document-page-action-row'),
                    child: Wrap(
                      spacing: WorkspaceTokens.space2,
                      runSpacing: WorkspaceTokens.space1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DocumentIcon(
                          key: const ValueKey('document-decoration-icon'),
                          editorState: widget.editorState,
                          node: widget.node,
                          icon: viewIcon,
                          documentId: view.id,
                          tabs: widget.tabs,
                          onChangeIcon: (icon) => _saveIconOrCover(icon: icon),
                          child: DecorationActionButton(
                            icon: FlowySvgs.add_icon_s,
                            label: hasIcon
                                ? LocaleKeys.document_plugins_cover_changeIcon
                                    .tr()
                                : LocaleKeys.document_plugins_cover_addIcon
                                    .tr(),
                          ),
                        ),
                        if (hasIcon)
                          DecorationActionButton(
                            key: const ValueKey(
                              'document-decoration-remove-icon',
                            ),
                            icon: FlowySvgs.add_icon_s,
                            label: LocaleKeys.document_plugins_cover_removeIcon
                                .tr(),
                            onTap: () =>
                                _saveIconOrCover(icon: EmojiIconData.none()),
                          ),
                        if (!hasCover)
                          DecorationActionButton(
                            key: const ValueKey(
                              'document-decoration-add-cover',
                            ),
                            icon: FlowySvgs.add_cover_s,
                            label:
                                LocaleKeys.document_plugins_cover_addCover.tr(),
                            onTap: () => _saveIconOrCover(
                              cover: (CoverType.asset, '1'),
                            ),
                          ),
                      ],
                    ),
                  )
                : null,
          ),
        ),
      );
    }
    return IgnorePointer(
      ignoring: !widget.editorState.editable,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final offset = _calculateIconLeft(constraints);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: _calculateOverallHeight(),
                    child: DocumentHeaderToolbar(
                      onIconOrCoverChanged: _saveIconOrCover,
                      node: widget.node,
                      editorState: widget.editorState,
                      hasCover: hasCover,
                      hasIcon: hasIcon,
                      offset: offset,
                      isCoverTitleHovered: isCoverTitleHovered,
                      documentId: view.id,
                      tabs: widget.tabs,
                    ),
                  ),
                  if (hasCover)
                    DocumentCover(
                      view: view,
                      editorState: widget.editorState,
                      node: widget.node,
                      coverType: coverType,
                      coverDetails: coverDetails,
                      onChangeCover: (type, details) =>
                          _saveIconOrCover(cover: (type, details)),
                    ),
                ],
              ),
              _buildAlignedTitle(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAlignedTitle(BuildContext context) {
    // keep the icon centered on the *first* line of the title, so a title that
    // wraps onto a second line does not drag the icon down with it.
    final titleLineHeight = coverTitleLineHeight(context);
    final iconTopInset = max(0.0, (titleLineHeight - kTitleIconSize) / 2);
    final titleTopInset = max(0.0, (kTitleIconSize - titleLineHeight) / 2);

    return DocumentHeaderContent(
      editorStyle: widget.editorState.editorStyle,
      child: MouseRegion(
        onEnter: (event) => isCoverTitleHovered.value = true,
        onExit: (event) => isCoverTitleHovered.value = false,
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasIcon) ...[
                Padding(
                  padding: EdgeInsets.only(top: iconTopInset),
                  child: _buildResizableIcon(
                    maxSize: max(0.0, (constraints.maxWidth - 14) / 2),
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: hasIcon ? titleTopInset : 0.0),
                  child: widget.titleBuilder?.call(widget.view) ??
                      CoverTitle(view: widget.view),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResizableIcon({
    bool optical = false,
    double maxSize = IconSize.maximum,
  }) =>
      ResizablePageIcon(
        view: view,
        binding: (widget.editorState, widget.node),
        editable: widget.editorState.editable,
        canResize: () => mounted && widget.editorState.editable && hasIcon,
        isSameTarget: (fresh) => fresh.isDocument,
        defaultSize: optical && isColorfulViewIcon(viewIcon)
            ? IconOpticalSize.resolve(
                role: IconOpticalRole.header,
                baseSize: kTitleIconSize,
              ).slotSize
            : kTitleIconSize,
        maxSize: maxSize,
        onSizeChanged: (size) {
          if (mounted && widget.editorState.editable) {
            setState(() => view = IconSize.applyTo(view, size));
          }
        },
        builder: (_, scale) => DocumentIcon(
          editorState: widget.editorState,
          node: widget.node,
          icon: viewIcon,
          documentId: view.id,
          emojiSize: kTitleIconSize * scale,
          opticalRole: optical ? IconOpticalRole.header : null,
          onChangeIcon: (icon) => _saveIconOrCover(icon: icon),
        ),
      );

  void _reload() => setState(() {});

  double _calculateIconLeft(BoxConstraints constraints) {
    final style = widget.editorState.editorStyle;
    final available = WorkspaceLayout.availableWidth(
      constraints,
      fallbackWidth: style.maxWidth ?? WorkspaceLayout.headerBreakpoint,
    );
    final editorWidth = min(available, style.maxWidth ?? available);
    return (available - editorWidth) / 2 +
        EditorStyleCustomizer.documentHeaderPadding(
          style.padding,
          textDirection: Directionality.of(context),
        ).left;
  }

  double _calculateOverallHeight() {
    if (!hasCover) {
      return kToolbarHeight;
    }
    final coverHeight =
        UniversalPlatform.isDesktopOrWeb ? kDesktopCoverHeight : kCoverHeight;
    return coverHeight + kToolbarHeight;
  }

  void _saveIconOrCover({
    (CoverType, String?)? cover,
    EmojiIconData? icon,
  }) async {
    if (!widget.editorState.editable) {
      return;
    }

    final transaction = widget.editorState.transaction;
    final coverType = widget.node.attributes[DocumentHeaderBlockKeys.coverType];
    final coverDetails =
        widget.node.attributes[DocumentHeaderBlockKeys.coverDetails];
    final Map<String, dynamic> attributes = {
      DocumentHeaderBlockKeys.coverType: coverType,
      DocumentHeaderBlockKeys.coverDetails: coverDetails,
      DocumentHeaderBlockKeys.icon:
          widget.node.attributes[DocumentHeaderBlockKeys.icon],
      CustomImageBlockKeys.imageType: '1',
    };
    if (cover != null) {
      attributes[DocumentHeaderBlockKeys.coverType] = cover.$1.toString();
      attributes[DocumentHeaderBlockKeys.coverDetails] = cover.$2;
    }
    if (icon != null) {
      attributes[DocumentHeaderBlockKeys.icon] = icon.emoji;
      widget.onIconChanged(icon);
    }

    // compatible with version <= 0.5.5.
    transaction.updateNode(widget.node, attributes);
    await widget.editorState.apply(transaction);

    // compatible with version > 0.5.5.
    unawaited(
      EditorMigration.migrateCoverIfNeeded(
        view,
        attributes,
        overwrite: true,
      ),
    );
  }

  bool _isTapInBounds(Offset offset) {
    if (_renderBox == null) {
      return false;
    }

    final localPosition = _renderBox!.globalToLocal(offset);
    return _renderBox!.paintBounds.contains(localPosition);
  }

  bool _isDragInBounds(Offset offset) {
    if (_renderBox == null) {
      return false;
    }

    final localPosition = _renderBox!.globalToLocal(offset);
    return _renderBox!.paintBounds.contains(localPosition);
  }
}

@visibleForTesting
class DocumentHeaderToolbar extends StatefulWidget {
  const DocumentHeaderToolbar({
    super.key,
    required this.node,
    required this.editorState,
    required this.hasCover,
    required this.hasIcon,
    required this.onIconOrCoverChanged,
    required this.offset,
    this.documentId,
    required this.isCoverTitleHovered,
    required this.tabs,
  });

  final Node node;
  final EditorState editorState;
  final bool hasCover;
  final bool hasIcon;
  final void Function({(CoverType, String?)? cover, EmojiIconData? icon})
      onIconOrCoverChanged;
  final double offset;
  final String? documentId;
  final ValueNotifier<bool> isCoverTitleHovered;
  final List<PickerTabType> tabs;

  @override
  State<DocumentHeaderToolbar> createState() => _DocumentHeaderToolbarState();
}

class _DocumentHeaderToolbarState extends State<DocumentHeaderToolbar> {
  final _popoverController = PopoverController();

  bool isPopoverOpen = false;
  VoidCallback? _releasePreview;

  void _showIconPicker() {
    if (!widget.editorState.editable || isPopoverOpen) return;
    _releasePreview = PreviewToolbarRegion.hold(context);
    setState(() => isPopoverOpen = true);
    _popoverController.show();
  }

  void _closeIconPicker() {
    _releasePreview?.call();
    _releasePreview = null;
    if (mounted && isPopoverOpen) setState(() => isPopoverOpen = false);
  }

  @override
  void didUpdateWidget(covariant DocumentHeaderToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.editorState.editable ||
        widget.hasIcon ||
        oldWidget.documentId != widget.documentId) {
      final release = _releasePreview;
      _releasePreview = null;
      isPopoverOpen = false;
      _popoverController.close();
      // A disappearing Popover closes without onClose. Release after the
      // current build so the ancestor reveal scope is not dirtied mid-layout.
      if (release != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => release());
      }
    }
  }

  @override
  void dispose() {
    final release = _releasePreview;
    _releasePreview = null;
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: AlignmentDirectional.bottomStart,
      padding: EdgeInsets.symmetric(horizontal: widget.offset),
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.isCoverTitleHovered,
        builder: (context, isHovered, child) => WorkspaceActionRow(
          keepVisible: isPopoverOpen || isHovered,
          children: buildRowChildren(),
        ),
      ),
    );
  }

  List<Widget> buildRowChildren() {
    if (widget.hasCover && widget.hasIcon) {
      return [];
    }

    final List<Widget> children = [];

    if (!widget.hasCover) {
      children.add(
        DecorationActionButton(
          icon: FlowySvgs.add_cover_s,
          label: LocaleKeys.document_plugins_cover_addCover.tr(),
          onTap: () => widget.onIconOrCoverChanged(
            cover: UniversalPlatform.isDesktopOrWeb
                ? (CoverType.asset, '1')
                : (CoverType.color, '0xffe8e0ff'),
          ),
        ),
      );
    }

    if (widget.hasIcon) {
      children.add(
        DecorationActionButton(
          icon: FlowySvgs.add_icon_s,
          label: LocaleKeys.document_plugins_cover_removeIcon.tr(),
          onTap: () => widget.onIconOrCoverChanged(icon: EmojiIconData.none()),
        ),
      );
    } else {
      Widget child = DecorationActionButton(
        icon: FlowySvgs.add_icon_s,
        label: LocaleKeys.document_plugins_cover_addIcon.tr(),
        onTap: UniversalPlatform.isDesktopOrWeb
            ? _showIconPicker
            : () async {
                final result = await context.push<EmojiIconData>(
                  MobileEmojiPickerScreen.routeName,
                );
                if (result != null) {
                  widget.onIconOrCoverChanged(icon: result);
                }
              },
      );

      if (UniversalPlatform.isDesktopOrWeb) {
        child = AppFlowyPopover(
          onClose: _closeIconPicker,
          controller: _popoverController,
          triggerActions: PopoverTriggerFlags.none,
          offset: const Offset(0, 8),
          direction: PopoverDirection.bottomWithCenterAligned,
          constraints: BoxConstraints.loose(const Size(360, 380)),
          margin: EdgeInsets.zero,
          child: child,
          popupBuilder: (BuildContext popoverContext) {
            return FlowyIconEmojiPicker(
              tabs: widget.tabs,
              documentId: widget.documentId,
              onSelectedEmoji: (r) {
                if (!mounted || !widget.editorState.editable) return;
                widget.onIconOrCoverChanged(icon: r.data);
                if (!r.keepOpen) _popoverController.close();
              },
            );
          },
        );
      }

      children.add(child);
    }

    return children;
  }
}

@visibleForTesting
class DocumentCover extends StatefulWidget {
  const DocumentCover({
    super.key,
    required this.view,
    required this.node,
    required this.editorState,
    required this.coverType,
    this.coverDetails,
    required this.onChangeCover,
    this.layoutBuilder,
    this.showCoverActions = true,
  });

  final ViewPB view;
  final Node node;
  final EditorState editorState;
  final CoverType coverType;
  final String? coverDetails;
  final void Function(CoverType type, String? details) onChangeCover;

  /// A host can remove cover controls without replacing the title tree.
  final bool showCoverActions;

  /// A page composes the same image and controls into its header cover slot.
  /// Null preserves the image-overlay layout for existing standalone callers.
  /// The cover State still owns the original upload/download/save callbacks.
  final Widget Function(Widget image, List<Widget> actions)? layoutBuilder;

  @override
  State<DocumentCover> createState() => DocumentCoverState();
}

class DocumentCoverState extends State<DocumentCover> {
  final popoverController = PopoverController();
  VoidCallback? _releasePreview;
  final _coverIdle = ValueNotifier(true);

  void _showCoverPicker(BuildContext context) {
    if (!widget.editorState.editable ||
        !_coverIdle.value ||
        !widget.showCoverActions ||
        _releasePreview != null) {
      return;
    }
    _releasePreview = PreviewToolbarRegion.hold(context);
    popoverController.show();
  }

  void _release() {
    _releasePreview?.call();
    _releasePreview = null;
  }

  @override
  void didUpdateWidget(covariant DocumentCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.editorState.editable ||
        !widget.showCoverActions ||
        oldWidget.view.id != widget.view.id) {
      final release = _releasePreview;
      _releasePreview = null;
      popoverController.close();
      if (release != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => release());
      }
    }
  }

  @override
  void dispose() {
    _coverIdle.dispose();
    final release = _releasePreview;
    _releasePreview = null;
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageCoverInteractionGate(
      allowed: _coverIdle,
      child: UniversalPlatform.isDesktopOrWeb
          ? _buildDesktopCover()
          : _buildMobileCover(),
    );
  }

  Widget _buildDesktopCover() {
    final image = DesktopCover(
      view: widget.view,
      editorState: widget.editorState,
      node: widget.node,
      coverType: widget.coverType,
      coverDetails: widget.coverDetails,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = widget.showCoverActions
            ? _buildCoverActions(
                compact: constraints.maxWidth < 480 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20,
              )
            : <Widget>[];
        final layoutBuilder = widget.layoutBuilder;
        if (layoutBuilder != null) return layoutBuilder(image, actions);
        return PageCoverLayout(
          width: constraints.maxWidth,
          fallbackHeight: kDesktopCoverHeight,
          view: widget.view,
          binding: (
            widget.editorState,
            widget.node,
            widget.coverType,
            widget.coverDetails
          ),
          editable: widget.editorState.editable && widget.showCoverActions,
          canResize: () =>
              mounted && widget.editorState.editable && widget.showCoverActions,
          builder: (context, height, grip) => SizedBox(
            height: height,
            child: WorkspacePageCover(
              image: image,
              resizeGrip: grip,
              actions: actions.isEmpty
                  ? null
                  : Wrap(
                      spacing: WorkspaceTokens.space1,
                      runSpacing: WorkspaceTokens.space1,
                      children: actions,
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileCover() {
    return SizedBox(
      height: kCoverHeight,
      child: Stack(
        children: [
          SizedBox(
            height: double.infinity,
            width: double.infinity,
            child: _buildCoverImage(),
          ),
          Positioned(
            bottom: 8,
            right: 12,
            child: Row(
              children: [
                IntrinsicWidth(
                  child: RoundedTextButton(
                    fontSize: 14,
                    onPressed: () {
                      showMobileBottomSheet(
                        context,
                        showHeader: true,
                        showDragHandle: true,
                        showCloseButton: true,
                        title:
                            LocaleKeys.document_plugins_cover_changeCover.tr(),
                        builder: (context) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 340,
                                minHeight: 80,
                              ),
                              child: UploadImageMenu(
                                limitMaximumImageSize: !_isLocalMode(),
                                supportTypes: const [
                                  UploadImageType.color,
                                  UploadImageType.local,
                                  UploadImageType.url,
                                  UploadImageType.unsplash,
                                ],
                                onSelectedLocalImages: (files) async {
                                  context.pop();

                                  if (files.isEmpty) {
                                    return;
                                  }

                                  widget.onChangeCover(
                                    CoverType.file,
                                    files.first.path,
                                  );
                                },
                                onSelectedAIImage: (_) {
                                  throw UnimplementedError();
                                },
                                onSelectedNetworkImage: (url) async {
                                  context.pop();
                                  widget.onChangeCover(CoverType.file, url);
                                },
                                onSelectedColor: (color) {
                                  context.pop();
                                  widget.onChangeCover(CoverType.color, color);
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                    fillColor: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.5),
                    height: 32,
                    title: LocaleKeys.document_plugins_cover_changeCover.tr(),
                  ),
                ),
                const HSpace(8.0),
                if (_downloadableCover != null) ...[
                  SizedBox.square(
                    dimension: 32.0,
                    child: DownloadCoverButton(onTap: _downloadCover),
                  ),
                  const HSpace(8.0),
                ],
                SizedBox.square(
                  dimension: 32.0,
                  child: DeleteCoverButton(
                    onTap: () => widget.onChangeCover(CoverType.none, null),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage() {
    final detail = widget.coverDetails;
    if (detail == null) {
      return const SizedBox.shrink();
    }
    switch (widget.coverType) {
      case CoverType.file:
        if (isURL(detail)) {
          final userProfilePB =
              context.read<DocumentBloc>().state.userProfilePB;
          return FlowyNetworkImage(
            url: detail,
            userProfilePB: userProfilePB,
            errorWidgetBuilder: (context, url, error) =>
                const SizedBox.shrink(),
          );
        }
        final imageFile = File(detail);
        if (!imageFile.existsSync()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onChangeCover(CoverType.none, null);
          });
          return const SizedBox.shrink();
        }
        return Image.file(
          imageFile,
          fit: BoxFit.cover,
        );
      case CoverType.asset:
        return Image.asset(
          widget.coverDetails!,
          fit: BoxFit.cover,
        );
      case CoverType.color:
        final color = widget.coverDetails?.tryToColor() ?? Colors.white;
        return Container(color: color);
      case CoverType.none:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildCoverActions({bool compact = false}) => [
        if (widget.editorState.editable)
          AppFlowyPopover(
            key: const ValueKey('document-decoration-cover'),
            controller: popoverController,
            triggerActions: PopoverTriggerFlags.none,
            offset: const Offset(0, 8),
            direction: PopoverDirection.bottomWithCenterAligned,
            constraints: const BoxConstraints(
              maxWidth: 540,
              maxHeight: 360,
              minHeight: 80,
            ),
            margin: EdgeInsets.zero,
            onClose: _release,
            child: Builder(
              builder: (actionContext) => DecorationActionButton(
                icon: FlowySvgs.add_cover_s,
                label: LocaleKeys.document_plugins_cover_changeCover.tr(),
                compact: compact,
                onTap: () => _showCoverPicker(actionContext),
              ),
            ),
            popupBuilder: (BuildContext popoverContext) {
              return UploadImageMenu(
                limitMaximumImageSize: !_isLocalMode(),
                supportTypes: const [
                  UploadImageType.color,
                  UploadImageType.local,
                  UploadImageType.url,
                  UploadImageType.unsplash,
                ],
                onSelectedLocalImages: (files) {
                  popoverController.close();
                  if (files.isEmpty) {
                    return;
                  }

                  final item = files.map((file) => file.path).first;
                  onCoverChanged(CoverType.file, item);
                },
                onSelectedAIImage: (_) {
                  throw UnimplementedError();
                },
                onSelectedNetworkImage: (url) {
                  popoverController.close();
                  onCoverChanged(CoverType.file, url);
                },
                onSelectedColor: (color) {
                  popoverController.close();
                  onCoverChanged(CoverType.color, color);
                },
              );
            },
          ),
        if (_downloadableCover != null) ...[
          DecorationActionButton(
            key: const ValueKey('document-decoration-download'),
            icon: FlowySvgs.download_s,
            label: LocaleKeys.document_plugins_cover_downloadCover.tr(),
            compact: compact,
            onTap: _downloadCover,
          ),
        ],
        if (widget.editorState.editable)
          DecorationActionButton(
            key: const ValueKey('document-decoration-remove-cover'),
            icon: FlowySvgs.delete_s,
            label: LocaleKeys.document_plugins_cover_removeCover.tr(),
            compact: compact,
            onTap: () => onCoverChanged(CoverType.none, null),
          ),
      ];

  /// The picture currently painted behind the page title, when there is one to
  /// save. Covers written after 0.5.5 live on the view, older ones on the node.
  @visibleForTesting
  DownloadableCoverImage? get downloadableCover => _downloadableCover;

  DownloadableCoverImage? get _downloadableCover {
    if (widget.view.cover != null) {
      return DownloadableCoverImage.fromPageStyleCover(widget.view.cover);
    }

    final details = widget.coverDetails;
    if (details == null || details.isEmpty) {
      return null;
    }
    return switch (widget.coverType) {
      CoverType.asset => DownloadableCoverImage.asset(
          details.startsWith('assets/')
              ? details
              : PageStyleCoverImageType.builtInImagePath(details),
        ),
      CoverType.file => DownloadableCoverImage.resolve(details),
      CoverType.color || CoverType.none => null,
    };
  }

  Future<void> _downloadCover() async {
    final cover = _downloadableCover;
    if (cover == null || !_coverIdle.value) {
      return;
    }
    _coverIdle.value = false;
    try {
      await downloadCoverImage(
        cover,
        userProfile: context.read<DocumentBloc>().state.userProfilePB,
      );
    } finally {
      if (mounted) _coverIdle.value = true;
    }
  }

  Future<void> onCoverChanged(CoverType type, String? details) async {
    if (!widget.editorState.editable || !_coverIdle.value) return;
    final source = widget;
    _coverIdle.value = false;
    try {
      final previousType = CoverType.fromString(
        widget.node.attributes[DocumentHeaderBlockKeys.coverType],
      );
      final previousDetails =
          widget.node.attributes[DocumentHeaderBlockKeys.coverDetails];

      bool isFileType(CoverType type, String? details) =>
          type == CoverType.file && details != null && !isURL(details);

      final localMode = (isFileType(type, details) ||
              isFileType(previousType, previousDetails)) &&
          _isLocalMode();

      if (isFileType(type, details)) {
        if (localMode) {
          details = await saveImageToLocalStorage(details!);
        } else {
          // else we should save the image to cloud storage
          (details, _) =
              await saveImageToCloudStorage(details!, source.view.id);
        }
      }
      if (!mounted ||
          !widget.editorState.editable ||
          widget.view.isLocked ||
          widget.view.id != source.view.id ||
          widget.node != source.node ||
          widget.editorState != source.editorState ||
          !samePageCoverSource(source.view, widget.view)) return;
      widget.onChangeCover(type, details);

      // After cover change,delete from localstorage if previous cover was image type
      if (isFileType(previousType, previousDetails) && localMode) {
        await deleteImageFromLocalStorage(previousDetails);
      }
    } finally {
      if (mounted) _coverIdle.value = true;
    }
  }

  bool _isLocalMode() {
    return context.read<DocumentBloc>().isLocalMode;
  }
}

@visibleForTesting
class DeleteCoverButton extends StatelessWidget {
  const DeleteCoverButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fillColor = UniversalPlatform.isDesktopOrWeb
        ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.5)
        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final svgColor = UniversalPlatform.isDesktopOrWeb
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onPrimary;
    return FlowyIconButton(
      hoverColor: Theme.of(context).colorScheme.surface,
      fillColor: fillColor,
      iconPadding: const EdgeInsets.all(5),
      width: 28,
      icon: FlowySvg(
        FlowySvgs.delete_s,
        color: svgColor,
      ),
      onPressed: onTap,
    );
  }
}

@visibleForTesting
class DownloadCoverButton extends StatelessWidget {
  const DownloadCoverButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fillColor = UniversalPlatform.isDesktopOrWeb
        ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.5)
        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final svgColor = UniversalPlatform.isDesktopOrWeb
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onPrimary;
    return FlowyIconButton(
      hoverColor: Theme.of(context).colorScheme.surface,
      fillColor: fillColor,
      iconPadding: const EdgeInsets.all(5),
      width: 28,
      tooltipText: LocaleKeys.document_plugins_cover_downloadCover.tr(),
      icon: FlowySvg(
        FlowySvgs.download_s,
        color: svgColor,
      ),
      onPressed: onTap,
    );
  }
}

@visibleForTesting
class DocumentIcon extends StatefulWidget {
  const DocumentIcon({
    super.key,
    required this.node,
    required this.editorState,
    required this.icon,
    required this.onChangeIcon,
    this.documentId,
    this.emojiSize = 60,
    this.opticalRole,
    this.child,
    this.tabs = const [
      PickerTabType.emoji,
      PickerTabType.icon,
      PickerTabType.custom,
    ],
  });

  final Node node;
  final EditorState editorState;
  final EmojiIconData icon;
  final String? documentId;
  final double emojiSize;
  final ValueChanged<EmojiIconData> onChangeIcon;
  final IconOpticalRole? opticalRole;

  /// Optional row label using the same native picker as the identity artwork.
  final Widget? child;
  final List<PickerTabType> tabs;

  @override
  State<DocumentIcon> createState() => _DocumentIconState();
}

class _DocumentIconState extends State<DocumentIcon> {
  final PopoverController _popoverController = PopoverController();
  VoidCallback? _releasePreview;

  void _showIconPicker() {
    if (!widget.editorState.editable || _releasePreview != null) return;
    _releasePreview = PreviewToolbarRegion.hold(context);
    _popoverController.show();
  }

  void _release() {
    _releasePreview?.call();
    _releasePreview = null;
  }

  @override
  void didUpdateWidget(covariant DocumentIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.editorState.editable ||
        oldWidget.documentId != widget.documentId) {
      final release = _releasePreview;
      _releasePreview = null;
      _popoverController.close();
      if (release != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => release());
      }
    }
  }

  @override
  void dispose() {
    final release = _releasePreview;
    _releasePreview = null;
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artwork = RawEmojiIconWidget(
      emoji: widget.icon,
      emojiSize: widget.emojiSize,
      opticalRole: isColorfulViewIcon(widget.icon) ? widget.opticalRole : null,
      lineHeight: 1,
    );
    Widget child = widget.child ??
        (widget.opticalRole == null
            ? artwork
            : MediaQuery.withNoTextScaling(child: artwork));

    if (!widget.editorState.editable) return child;

    if (UniversalPlatform.isDesktopOrWeb) {
      final label = widget.icon.isEmpty
          ? LocaleKeys.document_plugins_cover_addIcon.tr()
          : LocaleKeys.document_plugins_cover_changeIcon.tr();
      child = AppFlowyPopover(
        direction: PopoverDirection.bottomWithCenterAligned,
        controller: _popoverController,
        offset: const Offset(0, 8),
        constraints: BoxConstraints.loose(const Size(360, 380)),
        margin: EdgeInsets.zero,
        triggerActions: PopoverTriggerFlags.none,
        onClose: _release,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: TextButton(
            onPressed: _showIconPicker,
            style: WorkspaceChrome.controlStyle(context).copyWith(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              minimumSize: const WidgetStatePropertyAll(Size.zero),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Semantics(
              label: label,
              child: ExcludeSemantics(child: child),
            ),
          ),
        ),
        popupBuilder: (BuildContext popoverContext) {
          return FlowyIconEmojiPicker(
            initialType: widget.icon.toPickerTabType(),
            tabs: widget.tabs,
            documentId: widget.documentId,
            onSelectedEmoji: (r) {
              if (!mounted || !widget.editorState.editable) return;
              widget.onChangeIcon(r.data);
              if (!r.keepOpen) _popoverController.close();
            },
          );
        },
      );
    } else {
      child = GestureDetector(
        child: child,
        onTap: () async {
          final result = await context.push<EmojiIconData>(
            Uri(
              path: MobileEmojiPickerScreen.routeName,
              queryParameters: {
                MobileEmojiPickerScreen.iconSelectedType:
                    widget.icon.toPickerTabType()?.name,
              },
            ).toString(),
          );
          if (result != null) {
            widget.onChangeIcon(result);
          }
        },
      );
    }

    return child;
  }
}
