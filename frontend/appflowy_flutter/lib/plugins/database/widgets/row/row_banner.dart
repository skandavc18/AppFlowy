import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/base/emoji/emoji_picker_screen.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_banner_bloc.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_skeleton/text_card_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_builder.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_skeleton/text.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/plugins/database/widgets/row/row_action.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/plugins/shared/cover_type_ext.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide UploadImageMenu;
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/rounded_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';

import '../../../../shared/icon_emoji_picker/tab.dart';
import '../../../document/presentation/editor_plugins/plugins.dart';

/// We have the cover height as public as it is used in the row_detail.dart file
/// Used to determine the position of the row actions depending on if there is a cover or not.
///
const rowCoverHeight = 250.0;

/// Where every line of a row's content begins, and how far it stops short of
/// the far edge: the title, the properties, the rule, the notes and the
/// comments all answer to this one measure.
const rowDetailContentInset = 96.0;

/// Coverless popups still read like a page, not a form against the top edge.
const rowPopupTopSpace = 72.0;

/// How far the cover sits inside the popup, and how round its corners are.
const _coverInset = 10.0;
const _coverRadius = 14.0;

/// The cover a row wears before a cover choice has been persisted.
RowCoverPB defaultRowCover(String rowId) => RowCoverPB(
      data: FlowyGradientColor.forSeed(rowId).id,
      coverType: CoverTypePB.GradientCover,
    );

/// An absent cover is the new-row default; a present, empty cover is the
/// backend's persisted RemoveCover value. Never replace that choice with a
/// generated cover, including after the row is reopened.
RowCoverPB? effectiveRowCover(RowMetaPB rowMeta) {
  if (!rowMeta.hasCover()) {
    return defaultRowCover(rowMeta.id);
  }
  return rowMeta.cover.data.isEmpty ? null : rowMeta.cover;
}

/// The scroll surface must position its actions against the rendered cover,
/// not reserve a cover-sized gap after removal.
double rowCoverHeightFor(RowMetaPB rowMeta) =>
    effectiveRowCover(rowMeta) == null ? 0 : rowCoverHeight;

const _iconHeight = 60.0;
const _toolbarHeight = 40.0;

class RowBanner extends StatefulWidget {
  const RowBanner({
    super.key,
    required this.databaseController,
    required this.rowController,
    required this.cellBuilder,
    this.allowOpenAsFullPage = true,
    this.userProfile,
    this.spacious = false,
    this.contentInset = rowDetailContentInset,
  });

  final DatabaseController databaseController;
  final RowController rowController;
  final EditableCellBuilder cellBuilder;
  final bool allowOpenAsFullPage;
  final UserProfilePB? userProfile;
  final bool spacious;
  final double contentInset;

  @override
  State<RowBanner> createState() => _RowBannerState();
}

class _RowBannerState extends State<RowBanner> {
  final _isHovering = ValueNotifier(false);
  late final isLocalMode =
      (widget.userProfile?.workspaceType ?? WorkspaceTypePB.LocalW) ==
          WorkspaceTypePB.LocalW;

  @override
  void dispose() {
    _isHovering.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RowBannerBloc>(
      create: (context) => RowBannerBloc(
        viewId: widget.rowController.viewId,
        fieldController: widget.databaseController.fieldController,
        rowMeta: widget.rowController.rowMeta,
      )..add(const RowBannerEvent.initial()),
      child: BlocBuilder<RowBannerBloc, RowBannerState>(
        builder: (context, state) {
          return Column(
            children: [
              RowBannerHeader(
                rowMeta: state.rowMeta,
                userProfile: widget.userProfile,
                isLocalMode: isLocalMode,
                spacious: widget.spacious,
                contentInset: widget.contentInset,
                onIconChanged: (icon) => context
                    .read<RowBannerBloc>()
                    .add(RowBannerEvent.setIcon(icon ?? '')),
                onCoverChanged: (cover) {
                  context.read<RowBannerBloc>().add(
                        cover == null
                            ? const RowBannerEvent.removeCover()
                            : RowBannerEvent.setCover(cover),
                      );
                },
              ),
              VSpace(widget.spacious ? 16 : 8),
              _BannerTitle(
                cellBuilder: widget.cellBuilder,
                rowController: widget.rowController,
                spacious: widget.spacious,
                contentInset: widget.contentInset,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The cover, icon and decoration controls, independent of the row's cells.
class RowBannerHeader extends StatelessWidget {
  const RowBannerHeader({
    super.key,
    required this.rowMeta,
    required this.onIconChanged,
    required this.onCoverChanged,
    this.userProfile,
    this.isLocalMode = true,
    this.spacious = false,
    this.contentInset = rowDetailContentInset,
  });

  final RowMetaPB rowMeta;
  final ValueChanged<String?> onIconChanged;
  final ValueChanged<RowCoverPB?> onCoverChanged;
  final UserProfilePB? userProfile;
  final bool isLocalMode;
  final bool spacious;
  final double contentInset;

  @override
  Widget build(BuildContext context) {
    final cover = effectiveRowCover(rowMeta);
    final hasCover = cover != null;
    final hasIcon = rowMeta.icon.isNotEmpty;
    final decorationHeight = hasCover
        ? rowCoverHeight
        : (spacious ? rowPopupTopSpace : 0.0) +
            (hasIcon ? _iconHeight + 16 : 0.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            SizedBox(
              height: decorationHeight + _toolbarHeight,
              width: constraints.maxWidth,
              child: RowHeaderToolbar(
                offset: contentInset,
                hasIcon: hasIcon,
                hasCover: hasCover,
                quiet: spacious,
                onIconChanged: onIconChanged,
                onCoverChanged: onCoverChanged,
              ),
            ),
            if (cover != null)
              RowCover(
                rowId: rowMeta.id,
                cover: cover,
                userProfile: userProfile,
                onCoverChanged: (type, details, uploadType) {
                  onCoverChanged(
                    details == null
                        ? null
                        : RowCoverPB(
                            data: details,
                            uploadType: uploadType,
                            coverType: type.into(),
                          ),
                  );
                },
                isLocalMode: isLocalMode,
              ),
            if (hasIcon)
              Positioned(
                left: contentInset,
                bottom: hasCover
                    ? _toolbarHeight - _iconHeight / 2
                    : _toolbarHeight,
                child: RowIcon(
                  ///TODO: avoid hardcoding for [FlowyIconType]
                  icon: EmojiIconData(FlowyIconType.emoji, rowMeta.icon),
                  onIconChanged: onIconChanged,
                ),
              ),
          ],
        );
      },
    );
  }
}

class RowCover extends StatefulWidget {
  const RowCover({
    super.key,
    required this.rowId,
    required this.cover,
    this.userProfile,
    required this.onCoverChanged,
    this.isLocalMode = true,
  });

  final String rowId;
  final RowCoverPB cover;
  final UserProfilePB? userProfile;
  final void Function(
    CoverType type,
    String? details,
    FileUploadTypePB? uploadType,
  ) onCoverChanged;
  final bool isLocalMode;

  @override
  State<RowCover> createState() => _RowCoverState();
}

class _RowCoverState extends State<RowCover> {
  final popoverController = PopoverController();
  bool isOverlayButtonsHidden = true;
  bool isPopoverOpen = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowCoverHeight,
      child: MouseRegion(
        onEnter: (_) => setState(() => isOverlayButtonsHidden = false),
        onExit: (_) => setState(() => isOverlayButtonsHidden = true),
        child: Padding(
          // The popup is a card, so its cover sits inside it rather than
          // running to the edges and squaring off the corners.
          padding: const EdgeInsets.fromLTRB(
            _coverInset,
            _coverInset,
            _coverInset,
            0,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_coverRadius),
            child: Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: DesktopRowCover(
                    cover: widget.cover,
                    userProfile: widget.userProfile,
                  ),
                ),
                if (!isOverlayButtonsHidden || isPopoverOpen)
                  _buildCoverOverlayButtons(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverOverlayButtons(BuildContext context) {
    return Positioned(
      bottom: 20,
      right: 50,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppFlowyPopover(
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
            onClose: () => setState(() => isPopoverOpen = false),
            child: IntrinsicWidth(
              child: RoundedTextButton(
                height: 28.0,
                onPressed: () => popoverController.show(),
                hoverColor: Theme.of(context).colorScheme.surface,
                textColor: Theme.of(context).colorScheme.tertiary,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.5),
                title: LocaleKeys.document_plugins_cover_changeCover.tr(),
              ),
            ),
            popupBuilder: (BuildContext popoverContext) {
              isPopoverOpen = true;

              return UploadImageMenu(
                limitMaximumImageSize: !widget.isLocalMode,
                supportTypes: const [
                  UploadImageType.color,
                  UploadImageType.local,
                  UploadImageType.url,
                  UploadImageType.unsplash,
                ],
                onSelectedAIImage: (_) => throw UnimplementedError(),
                onSelectedLocalImages: (files) {
                  popoverController.close();
                  if (files.isEmpty) {
                    return;
                  }

                  final item = files.map((file) => file.path).first;
                  onCoverChanged(
                    CoverType.file,
                    item,
                    widget.isLocalMode
                        ? FileUploadTypePB.LocalFile
                        : FileUploadTypePB.CloudFile,
                  );
                },
                onSelectedNetworkImage: (url) {
                  popoverController.close();
                  onCoverChanged(
                    CoverType.file,
                    url,
                    FileUploadTypePB.NetworkFile,
                  );
                },
                onSelectedColor: (color) {
                  popoverController.close();
                  onCoverChanged(
                    CoverType.color,
                    color,
                    FileUploadTypePB.LocalFile,
                  );
                },
              );
            },
          ),
          const HSpace(10),
          DeleteCoverButton(
            onTap: () => widget.onCoverChanged(CoverType.none, null, null),
          ),
        ],
      ),
    );
  }

  Future<void> onCoverChanged(
    CoverType type,
    String? details,
    FileUploadTypePB? uploadType,
  ) async {
    if (type == CoverType.file && details != null && !isURL(details)) {
      if (widget.isLocalMode) {
        details = await saveImageToLocalStorage(details);
      } else {
        // else we should save the image to cloud storage
        (details, _) = await saveImageToCloudStorage(details, widget.rowId);
      }
    }
    widget.onCoverChanged(type, details, uploadType);
  }
}

class DesktopRowCover extends StatefulWidget {
  const DesktopRowCover({super.key, required this.cover, this.userProfile});

  final RowCoverPB cover;
  final UserProfilePB? userProfile;

  @override
  State<DesktopRowCover> createState() => _DesktopRowCoverState();
}

class _DesktopRowCoverState extends State<DesktopRowCover> {
  RowCoverPB get cover => widget.cover;

  @override
  Widget build(BuildContext context) {
    if (cover.coverType == CoverTypePB.FileCover) {
      return SizedBox.expand(
        child: AFImage(
          url: cover.data,
          uploadType: cover.uploadType,
          userProfile: widget.userProfile,
        ),
      );
    }

    if (cover.coverType == CoverTypePB.AssetCover) {
      return SizedBox.expand(
        child: Image.asset(
          PageStyleCoverImageType.builtInImagePath(cover.data),
          fit: BoxFit.cover,
        ),
      );
    }

    if (cover.coverType == CoverTypePB.ColorCover) {
      final color = FlowyTint.fromId(cover.data)?.color(context) ??
          cover.data.tryToColor();
      return ColoredBox(
        color: color ?? Colors.transparent,
        child: const SizedBox.expand(),
      );
    }

    if (cover.coverType == CoverTypePB.GradientCover) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: FlowyGradientColor.fromId(cover.data).linear,
        ),
        child: const SizedBox.expand(),
      );
    }

    return const SizedBox.shrink();
  }
}

class RowHeaderToolbar extends StatefulWidget {
  const RowHeaderToolbar({
    super.key,
    required this.offset,
    required this.hasIcon,
    required this.hasCover,
    required this.onIconChanged,
    required this.onCoverChanged,
    this.quiet = false,
  });

  final double offset;
  final bool hasIcon;
  final bool hasCover;
  final bool quiet;

  /// Returns null if the icon is removed.
  ///
  final void Function(String? icon) onIconChanged;

  /// Returns null if the cover is removed.
  ///
  final void Function(RowCoverPB? cover) onCoverChanged;

  @override
  State<RowHeaderToolbar> createState() => _RowHeaderToolbarState();
}

class _RowHeaderToolbarState extends State<RowHeaderToolbar> {
  final popoverController = PopoverController();
  final bool isDesktop = UniversalPlatform.isDesktopOrWeb;

  bool isHidden = UniversalPlatform.isDesktopOrWeb;
  bool isPopoverOpen = false;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return const SizedBox.shrink();
    }
    final muted = widget.quiet ? Theme.of(context).hintColor : null;

    return MouseRegion(
      opaque: false,
      onEnter: (_) => setState(() => isHidden = false),
      onExit: isPopoverOpen ? null : (_) => setState(() => isHidden = true),
      child: Container(
        alignment: Alignment.bottomLeft,
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: widget.offset),
        child: SizedBox(
          height: 28,
          child: Visibility(
            visible: !widget.hasCover || !isHidden || isPopoverOpen,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.hasCover)
                  FlowyButton(
                    resetHoverOnRebuild: false,
                    useIntrinsicWidth: true,
                    leftIconSize: const Size.square(18),
                    leftIcon: FlowySvg(FlowySvgs.add_cover_s, color: muted),
                    text: FlowyText.small(
                      LocaleKeys.document_plugins_cover_addCover.tr(),
                      color: muted,
                    ),
                    onTap: () => widget.onCoverChanged(
                      RowCoverPB(
                        data: isDesktop ? '1' : '0xffe8e0ff',
                        uploadType: FileUploadTypePB.LocalFile,
                        coverType: isDesktop
                            ? CoverTypePB.AssetCover
                            : CoverTypePB.ColorCover,
                      ),
                    ),
                  ),
                if (!widget.hasIcon)
                  AppFlowyPopover(
                    controller: popoverController,
                    onClose: () => setState(() => isPopoverOpen = false),
                    offset: const Offset(0, 8),
                    direction: PopoverDirection.bottomWithCenterAligned,
                    constraints: BoxConstraints.loose(const Size(360, 380)),
                    margin: EdgeInsets.zero,
                    triggerActions: PopoverTriggerFlags.none,
                    popupBuilder: (_) {
                      isPopoverOpen = true;
                      return FlowyIconEmojiPicker(
                        tabs: const [PickerTabType.emoji],
                        onSelectedEmoji: (result) {
                          widget.onIconChanged(result.emoji);
                          popoverController.close();
                        },
                      );
                    },
                    child: FlowyButton(
                      useIntrinsicWidth: true,
                      leftIconSize: const Size.square(18),
                      leftIcon: FlowySvg(FlowySvgs.add_icon_s, color: muted),
                      text: FlowyText.small(
                        widget.hasIcon
                            ? LocaleKeys.document_plugins_cover_removeIcon.tr()
                            : LocaleKeys.document_plugins_cover_addIcon.tr(),
                        color: muted,
                      ),
                      onTap: () async {
                        if (!isDesktop) {
                          final result = await context.push<EmojiIconData>(
                            MobileEmojiPickerScreen.routeName,
                          );

                          if (result != null) {
                            widget.onIconChanged(result.emoji);
                          }
                        } else {
                          popoverController.show();
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RowIcon extends StatefulWidget {
  const RowIcon({
    super.key,
    required this.icon,
    required this.onIconChanged,
  });

  final EmojiIconData icon;
  final void Function(String?) onIconChanged;

  @override
  State<RowIcon> createState() => _RowIconState();
}

class _RowIconState extends State<RowIcon> {
  final controller = PopoverController();

  @override
  Widget build(BuildContext context) {
    if (widget.icon.isEmpty) {
      return const SizedBox.shrink();
    }

    return AppFlowyPopover(
      controller: controller,
      offset: const Offset(0, 8),
      direction: PopoverDirection.bottomWithCenterAligned,
      constraints: BoxConstraints.loose(const Size(360, 380)),
      margin: EdgeInsets.zero,
      popupBuilder: (_) => FlowyIconEmojiPicker(
        tabs: const [PickerTabType.emoji],
        onSelectedEmoji: (result) {
          controller.close();
          widget.onIconChanged(result.emoji);
        },
      ),
      child: EmojiIconWidget(emoji: widget.icon),
    );
  }
}

class _BannerTitle extends StatelessWidget {
  const _BannerTitle({
    required this.cellBuilder,
    required this.rowController,
    required this.spacious,
    required this.contentInset,
  });

  final EditableCellBuilder cellBuilder;
  final RowController rowController;
  final bool spacious;
  final double contentInset;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RowBannerBloc, RowBannerState>(
      builder: (context, state) {
        // The primary field is read from the backend, while the cell is built
        // against the field controller — so it can be named before it is known.
        final primaryField = state.primaryField;
        final known = primaryField != null &&
            cellBuilder.databaseController.fieldController
                    .getField(primaryField.id) !=
                null;
        final children = [
          if (known)
            Expanded(
              child: cellBuilder.buildCustom(
                CellContext(
                  fieldId: primaryField.id,
                  rowId: rowController.rowId,
                ),
                skinMap: EditableCellSkinMap(
                  textSkin: _TitleSkin(spacious: spacious),
                ),
              ),
            ),
        ];

        return Padding(
          padding: EdgeInsets.only(
            left: contentInset,
            right: spacious ? contentInset : 0,
          ),
          child: Row(children: children),
        );
      },
    );
  }
}

class _TitleSkin extends IEditableTextCellSkin {
  _TitleSkin({required this.spacious});

  final bool spacious;

  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    ValueNotifier<bool> compactModeNotifier,
    TextCellBloc bloc,
    FocusNode focusNode,
    TextEditingController textEditingController,
  ) {
    return RowBannerTitleField(
      controller: textEditingController,
      focusNode: focusNode,
      spacious: spacious,
      onEditingComplete: () {
        bloc.add(TextCellEvent.updateText(textEditingController.text));
      },
    );
  }
}

/// The editable page title, with a reading-first presentation in a popup.
/// The host owns the field controller and persistence, just as for any cell.
class RowBannerTitleField extends StatelessWidget {
  const RowBannerTitleField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onEditingComplete,
    this.spacious = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onEditingComplete;
  final bool spacious;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              focusNode.unfocus(),
          const SimpleActivator(LogicalKeyboardKey.enter): () =>
              focusNode.unfocus(),
        },
        child: TextField(
          key: const ValueKey('row-banner-title'),
          controller: controller,
          focusNode: focusNode,
          autofocus: !spacious,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: spacious ? 40 : 28,
                height: spacious ? 1.18 : null,
                fontWeight: spacious ? FontWeight.w700 : null,
                fontVariations: spacious
                    ? flowyFontVariationsForWeight(FontWeight.w700)
                    : null,
                letterSpacing: spacious ? -0.8 : null,
              ),
          maxLines: null,
          decoration: InputDecoration(
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            hintText: LocaleKeys.grid_row_titlePlaceholder.tr(),
            isDense: true,
            isCollapsed: true,
          ),
          onEditingComplete: onEditingComplete,
        ),
      );
}

class RowActionButton extends StatelessWidget {
  const RowActionButton({super.key, required this.rowController});

  final RowController rowController;

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      direction: PopoverDirection.bottomWithLeftAligned,
      popupBuilder: (context) => RowActionList(rowController: rowController),
      child: FlowyTooltip(
        message: LocaleKeys.grid_rowPage_moreRowActions.tr(),
        child: FlowyIconButton(
          width: 20,
          height: 20,
          icon: const FlowySvg(FlowySvgs.details_horizontal_s),
          iconColorOnHover: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
