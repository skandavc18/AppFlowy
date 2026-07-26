import 'dart:io';
import 'dart:math';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:string_validator/string_validator.dart';

enum ResizableImageState {
  loading,
  loaded,
  failed,
}

class ResizableImage extends StatefulWidget {
  const ResizableImage({
    super.key,
    required this.type,
    required this.alignment,
    required this.editable,
    required this.onResize,
    required this.width,
    required this.src,
    this.height,
    this.onResizeHeight,
    this.onDoubleTap,
    this.onStateChange,
    this.overlay,
    this.caption,
  });

  final String src;
  final CustomImageType type;
  final double width;
  final double? height;
  final Alignment alignment;
  final bool editable;
  final VoidCallback? onDoubleTap;
  final ValueChanged<ResizableImageState>? onStateChange;

  /// Chrome pinned to the picture's top-right corner, inside the resized frame.
  final Widget? overlay;

  /// Rendered under the picture at the same width.
  final Widget? caption;

  final void Function(double width) onResize;

  /// Set when the block is allowed to be framed to an explicit height.
  final void Function(double height)? onResizeHeight;

  @override
  State<ResizableImage> createState() => _ResizableImageState();
}

const _kImageBlockComponentMinWidth = 30.0;
const _kImageBlockComponentMinHeight = 60.0;

class _ResizableImageState extends State<ResizableImage> {
  final documentService = DocumentService();

  Widget? _cacheImage;

  UserProfilePB? _userProfilePB;

  @override
  void initState() {
    super.initState();

    _userProfilePB = context.read<UserWorkspaceBloc?>()?.state.userProfile ??
        context.read<DocumentBloc>().state.userProfilePB;

    _reportLocalFileState();
  }

  @override
  void didUpdateWidget(covariant ResizableImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The cached child bakes in the source and how it fills its box.
    if (oldWidget.src != widget.src ||
        (oldWidget.height == null) != (widget.height == null)) {
      _cacheImage = null;
    }
    if (oldWidget.src != widget.src) {
      _reportLocalFileState();
    }
  }

  /// A local file has no download to listen to, so nothing would ever move the
  /// block out of its loading state — and the hover menu stays hidden while it
  /// thinks the picture is still arriving.
  void _reportLocalFileState() {
    if (isURL(widget.src)) {
      return;
    }
    final exists = widget.src.isNotEmpty && File(widget.src).existsSync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onStateChange?.call(
        exists ? ResizableImageState.loaded : ResizableImageState.failed,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlay;
    return ResizableMedia(
      width: max(_kImageBlockComponentMinWidth, widget.width),
      minWidth: _kImageBlockComponentMinWidth,
      height: widget.height,
      minHeight: _kImageBlockComponentMinHeight,
      maxHeight: 2400,
      alignment: widget.alignment,
      editable: widget.editable,
      onResize: widget.onResize,
      onResizeHeight: widget.onResizeHeight,
      footer: widget.caption,
      frameBuilder: overlay == null
          ? null
          : (frame) => Stack(
                clipBehavior: Clip.none,
                children: [
                  frame,
                  Positioned(top: 8, right: 8, child: overlay),
                ],
              ),
      child: GestureDetector(
        onDoubleTap: widget.onDoubleTap,
        child: ClipRRect(
          borderRadius: EditorSurfaceStyle.embedBorderRadius,
          child: _buildResizableImage(context),
        ),
      ),
    );
  }

  Widget _buildResizableImage(BuildContext context) {
    final hasFixedHeight = widget.height != null;
    // A framed picture stretches to the box the handles define: the aspect
    // ratio follows the frame and none of the photo is cropped away.
    final fit = hasFixedHeight ? BoxFit.fill : BoxFit.contain;
    Widget child;
    final src = widget.src;
    if (isURL(src)) {
      // No explicit size: the resizable frame owns the box, and the picture
      // scales to whatever the drag handles leave it.
      _cacheImage ??= FlowyNetworkImage(
        url: widget.src,
        fit: fit,
        userProfilePB: _userProfilePB,
        onImageLoaded: (isImageInCache) {
          if (isImageInCache) {
            widget.onStateChange?.call(ResizableImageState.loaded);
          }
        },
        progressIndicatorBuilder: (context, _, progress) {
          if (progress.totalSize != null) {
            if (progress.progress == 1) {
              widget.onStateChange?.call(ResizableImageState.loaded);
            } else {
              widget.onStateChange?.call(ResizableImageState.loading);
            }
          }

          return _buildLoading(context);
        },
        errorWidgetBuilder: (_, __, error) {
          widget.onStateChange?.call(ResizableImageState.failed);
          return _ImageLoadFailedWidget(
            width: widget.width,
            error: error,
            onRetry: () {
              setState(() {
                _cacheImage = null;
                final retryCounter = FlowyNetworkRetryCounter();
                retryCounter.clear(tag: src, url: src);
              });
            },
          );
        },
      );

      child = _cacheImage!;
    } else {
      // load local file
      _cacheImage ??= Image.file(
        File(src),
        fit: fit,
        errorBuilder: (_, error, __) {
          widget.onStateChange?.call(ResizableImageState.failed);
          return _ImageLoadFailedWidget(
            width: widget.width,
            error: error,
            onRetry: () => setState(() => _cacheImage = null),
          );
        },
      );
      child = _cacheImage!;
    }

    return hasFixedHeight ? SizedBox.expand(child: child) : child;
  }

  Widget _buildLoading(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.fromSize(
            size: const Size(18, 18),
            child: const CircularProgressIndicator(),
          ),
          SizedBox.fromSize(size: const Size(10, 10)),
          Text(AppFlowyEditorL10n.current.loading),
        ],
      ),
    );
  }
}

class _ImageLoadFailedWidget extends StatelessWidget {
  const _ImageLoadFailedWidget({
    required this.width,
    required this.error,
    required this.onRetry,
  });

  final double width;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = _getErrorMessage();
    return Container(
      height: 160,
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(4.0)),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FlowySvg(
            FlowySvgs.broken_image_xl,
            size: Size.square(36),
          ),
          FlowyText(
            AppFlowyEditorL10n.current.imageLoadFailed,
            fontSize: 14,
          ),
          const VSpace(4),
          if (error != null)
            FlowyText(
              error,
              textAlign: TextAlign.center,
              color: Theme.of(context).hintColor.withValues(alpha: 0.6),
              fontSize: 10,
              maxLines: 2,
            ),
          const VSpace(12),
          Listener(
            onPointerDown: (event) {
              onRetry();
            },
            child: OutlinedRoundedButton(
              text: LocaleKeys.chat_retry.tr(),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  String? _getErrorMessage() {
    if (error is HttpExceptionWithStatus) {
      return 'Error ${(error as HttpExceptionWithStatus).statusCode}';
    }

    return null;
  }
}
