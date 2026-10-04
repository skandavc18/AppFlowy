import 'dart:async';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:universal_platform/universal_platform.dart';

class InteractiveImageToolbar extends StatelessWidget {
  const InteractiveImageToolbar({
    super.key,
    required this.currentImage,
    required this.imageCount,
    required this.isFirstIndex,
    required this.isLastIndex,
    required this.currentScale,
    required this.onPrevious,
    required this.onNext,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onScaleChanged,
    this.onDelete,
    this.userProfile,
    this.imageName,
    this.hovered = false,
    this.actions = const MediaActionService(),
    this.onClose,
    this.onExtractText,
    this.onEdit,
    this.onFit,
    this.canRead,
    this.enabled = true,
  });

  final ImageBlockData currentImage;
  final String? imageName;
  final bool hovered;
  final MediaActionService actions;
  final int imageCount;
  final bool isFirstIndex;
  final bool isLastIndex;
  final int currentScale;

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final Function(double scale) onScaleChanged;
  final UserProfilePB? userProfile;
  final VoidCallback? onDelete;
  final VoidCallback? onClose;
  final VoidCallback? onExtractText;
  final VoidCallback? onEdit;
  final VoidCallback? onFit;
  final bool Function()? canRead;
  final bool enabled;

  bool _current(BuildContext context) =>
      context.mounted &&
      enabled &&
      (canRead?.call() ?? true) &&
      ModalRoute.of(context)?.isCurrent != false;

  void _close(BuildContext context) {
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (onClose != null) {
      onClose!();
      return;
    }
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true && route!.navigator!.canPop()) {
      route.navigator!.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DocumentViewportStyle.of(context);
    return DocumentViewportBar(
      key: const ValueKey('photo-fullscreen-chrome'),
      background: style.canvas,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  imageName ?? MediaActionSource.image(currentImage).name,
                  key: const ValueKey('photo-fullscreen-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: style.textPrimary,
                      ),
                ),
              ),
              // Exit belongs to the route, never to the overflowing tool row.
              WorkspaceControlButton(
                key: const ValueKey('photo-fullscreen-close'),
                icon: Icons.close_rounded,
                tooltip: 'Exit full screen (Esc)',
                onPressed: () => _close(context),
              ),
            ],
          ),
          SingleChildScrollView(
            key: const ValueKey('photo-toolbar-scroll'),
            scrollDirection: Axis.horizontal,
            reverse: true,
            padding: EdgeInsets.only(
              top: MediaQuery.textScalerOf(context).scale(10) * 1.2 + 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (imageCount > 1) ...[
                  WorkspaceControlButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: LocaleKeys
                        .document_imageBlock_interactiveViewer_toolbar_previousImageTooltip
                        .tr(),
                    onPressed: enabled && !isFirstIndex ? onPrevious : null,
                  ),
                  WorkspaceControlButton(
                    icon: Icons.arrow_forward_rounded,
                    tooltip: LocaleKeys
                        .document_imageBlock_interactiveViewer_toolbar_nextImageTooltip
                        .tr(),
                    onPressed: enabled && !isLastIndex ? onNext : null,
                  ),
                ],
                WorkspaceControlButton(
                  icon: Icons.remove_rounded,
                  tooltip: LocaleKeys
                      .document_imageBlock_interactiveViewer_toolbar_zoomOutTooltip
                      .tr(),
                  onPressed: enabled ? onZoomOut : null,
                ),
                DocumentViewportLabel(label: '$currentScale%'),
                AppMenuIconButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  tooltip: LocaleKeys
                      .document_imageBlock_interactiveViewer_toolbar_changeZoomLevelTooltip
                      .tr(),
                  enabled: enabled,
                  entries: () => [
                    AppMenuCustom(
                      builder: (_) => SizedBox(
                        width: 220,
                        child: _ScaleSlider(
                          currentScale: currentScale,
                          onScaleChanged: (value) {
                            // The zoom menu itself covers this route, so check
                            // the image binding without requiring current route.
                            if (enabled && (canRead?.call() ?? true)) {
                              onScaleChanged(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                WorkspaceControlButton(
                  icon: Icons.add_rounded,
                  tooltip: LocaleKeys
                      .document_imageBlock_interactiveViewer_toolbar_zoomInTooltip
                      .tr(),
                  onPressed: enabled ? onZoomIn : null,
                ),
                DocumentViewportFitButton(
                  onPressed: enabled ? onFit ?? () => onScaleChanged(1) : null,
                ),
                if (onEdit != null)
                  WorkspaceControlButton(
                    icon: Icons.tune_rounded,
                    tooltip: 'Edit image',
                    onPressed: enabled ? onEdit : null,
                  ),
                if (onExtractText != null)
                  WorkspaceControlButton(
                    icon: Icons.document_scanner_rounded,
                    tooltip: 'Extract text',
                    onPressed: enabled ? onExtractText : null,
                  ),
                if (onDelete != null)
                  WorkspaceControlButton(
                    icon: Icons.delete_rounded,
                    tooltip: LocaleKeys
                        .document_imageBlock_interactiveViewer_toolbar_deleteImageTooltip
                        .tr(),
                    onPressed: !enabled
                        ? null
                        : () {
                            final route = ModalRoute.of(context);
                            if (route?.isCurrent != true) return;
                            onDelete!();
                            // Deletion may open a confirmation dialog. Never pop it.
                            if (context.mounted && route!.isCurrent) {
                              _close(context);
                            }
                          },
                  ),
                if (!UniversalPlatform.isMobile)
                  WorkspaceControlButton(
                    icon: currentImage.isNotInternal
                        ? Icons.open_in_new_rounded
                        : Icons.download_rounded,
                    tooltip: currentImage.isNotInternal
                        ? LocaleKeys
                            .document_imageBlock_interactiveViewer_toolbar_openLocalImage
                            .tr()
                        : LocaleKeys
                            .document_imageBlock_interactiveViewer_toolbar_downloadImage
                            .tr(),
                    onPressed: enabled
                        ? () => unawaited(_locateOrDownloadImage(context))
                        : null,
                  ),
                MediaActionButtons(
                  source: MediaActionSource.image(
                    currentImage,
                    userProfile: userProfile,
                    name: imageName,
                  ),
                  actions: actions,
                  decorated: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _locateOrDownloadImage(BuildContext context) async {
    if (!_current(context)) return;
    final target = MediaActionSource.image(
      currentImage,
      userProfile: userProfile,
      name: imageName,
    );
    try {
      if (currentImage.isLocal) {
        final file = await materializeMediaFile(
          source: target.source,
          name: target.name,
        );
        if (!context.mounted || !_current(context)) return;
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done) {
          throw StateError('Unable to open the image.');
        }
      } else if (currentImage.isNotInternal) {
        if (!await afLaunchUrlString(target.source)) {
          throw StateError('Unable to open the image.');
        }
      } else if (target.httpHeaders.isEmpty) {
        return showSnapBar(
          context,
          LocaleKeys.document_plugins_image_imageDownloadFailedToken.tr(),
        );
      } else {
        await downloadMedia(
          source: target.source,
          name: target.name,
          httpHeaders: target.httpHeaders,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showSnapBar(
          context,
          LocaleKeys.document_plugins_image_imageDownloadFailed.tr(),
        );
      }
    }
  }
}

class _ScaleSlider extends StatefulWidget {
  const _ScaleSlider({
    required this.currentScale,
    required this.onScaleChanged,
  });
  final int currentScale;
  final ValueChanged<double> onScaleChanged;

  @override
  State<_ScaleSlider> createState() => _ScaleSliderState();
}

class _ScaleSliderState extends State<_ScaleSlider> {
  late double _scale = (widget.currentScale / 100).clamp(0.5, 5.0);

  @override
  Widget build(BuildContext context) => Slider(
        min: 0.5,
        max: 5,
        value: _scale,
        label: '${(_scale * 100).round()}%',
        onChanged: (value) {
          setState(() => _scale = value);
          widget.onScaleChanged(value);
        },
      );
}
