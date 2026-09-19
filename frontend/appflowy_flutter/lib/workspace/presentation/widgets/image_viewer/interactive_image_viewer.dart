import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_toolbar.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const double _minScaleFactor = .5;
const double _maxScaleFactor = 5;

class InteractiveImageViewer extends StatefulWidget {
  const InteractiveImageViewer({
    super.key,
    this.userProfile,
    required this.imageProvider,
    this.actions = const MediaActionService(),
  });

  final UserProfilePB? userProfile;
  final AFImageProvider imageProvider;
  final MediaActionService actions;

  @override
  State<InteractiveImageViewer> createState() => _InteractiveImageViewerState();
}

class _InteractiveImageViewerState extends State<InteractiveImageViewer> {
  final TransformationController controller = TransformationController();
  final focusNode = FocusNode();

  int currentScale = 100;
  late int currentIndex = widget.imageProvider.initialIndex;

  bool get isLastIndex => currentIndex == widget.imageProvider.imageCount - 1;
  bool get isFirstIndex => currentIndex == 0;

  ImageBlockData get currentImage =>
      widget.imageProvider.getImage(currentIndex);

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    _clampIndex();
  }

  @override
  void didUpdateWidget(covariant InteractiveImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _clampIndex();
  }

  void _clampIndex() {
    currentIndex = widget.imageProvider.imageCount == 0
        ? 0
        : currentIndex.clamp(0, widget.imageProvider.imageCount - 1);
  }

  void _onControllerChanged() {
    final scale = controller.value.getMaxScaleOnAxis();
    final percentage = (scale * 100).toInt();
    setState(() => currentScale = percentage);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // A table/local-auth viewer need not live under a document at all. These
    // optional subscriptions also pick up profile refreshes while it is open.
    final documentProfile = context.select<DocumentBloc?, UserProfilePB?>(
      (bloc) => bloc?.state.userProfilePB,
    );
    final workspaceProfile = context.select<UserWorkspaceBloc?, UserProfilePB?>(
      (bloc) => bloc?.state.userProfile,
    );
    final userProfile =
        widget.userProfile ?? documentProfile ?? workspaceProfile;

    // The hover region is deliberately non-opaque. Keep its transparent parts
    // from admitting the dialog barrier into the image's gesture arena.
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: Focus(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: (_, event) => _handleKey(event, size),
        // Keep the autofocus node ABOVE the hover region: otherwise its focus
        // would permanently reveal the actions even with the pointer outside.
        child: MediaHoverRegion(
          builder: (context, hovered) => Stack(
            fit: StackFit.expand,
            children: [
              if (widget.imageProvider.imageCount > 0) ...[
                SizedBox.expand(
                  child: InteractiveViewer(
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    transformationController: controller,
                    constrained: false,
                    minScale: _minScaleFactor,
                    maxScale: _maxScaleFactor,
                    scaleFactor: 500,
                    child: SizedBox(
                      height: size.height,
                      width: size.width,
                      child: GestureDetector(
                        // Keep the existing double-click-to-close behavior.
                        onDoubleTap: () => Navigator.of(context).pop(),
                        child: widget.imageProvider.renderImage(
                          context,
                          currentIndex,
                          userProfile,
                        ),
                      ),
                    ),
                  ),
                ),
                InteractiveImageToolbar(
                  currentImage: currentImage,
                  imageName: widget.imageProvider.getImageName(currentIndex),
                  imageCount: widget.imageProvider.imageCount,
                  isFirstIndex: isFirstIndex,
                  isLastIndex: isLastIndex,
                  currentScale: currentScale,
                  userProfile: userProfile,
                  actions: widget.actions,
                  hovered: hovered,
                  onPrevious: () => _move(-1),
                  onNext: () => _move(1),
                  onZoomIn: () => _zoom(1.1, size),
                  onZoomOut: () => _zoom(.9, size),
                  onScaleChanged: (scale) {
                    final currentScale = controller.value.getMaxScaleOnAxis();
                    final scaleStep = scale / currentScale;
                    _zoom(scaleStep, size);
                  },
                  onDelete: widget.imageProvider.onDeleteImage == null
                      ? null
                      : () => widget.imageProvider.onDeleteImage
                          ?.call(currentIndex),
                ),
              ] else
                Align(
                  alignment: Alignment.topRight,
                  child: Material(
                    type: MaterialType.transparency,
                    child: CloseButton(
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKey(KeyEvent event, Size size) {
    final key = event.logicalKey;
    // The explicit toolbar delete is the only destructive action. Do not let
    // these keys reach a selected database row or the document underneath.
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) {
        unawaited(Navigator.of(context).maybePop());
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _move(1);
    } else if (key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd ||
        (key == LogicalKeyboardKey.equal &&
            HardwareKeyboard.instance.isShiftPressed)) {
      _zoom(1.1, size);
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoom(.9, size);
    } else if (key == LogicalKeyboardKey.numpad0 ||
        key == LogicalKeyboardKey.digit0) {
      controller.value = Matrix4.identity();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _move(int steps) {
    if (widget.imageProvider.imageCount == 0) return;
    setState(() {
      final index = currentIndex + steps;
      currentIndex = index.clamp(0, widget.imageProvider.imageCount - 1);
    });
  }

  void _zoom(double scaleStep, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scenePointBefore = controller.toScene(center);
    final currentScale = controller.value.getMaxScaleOnAxis();
    final newScale = (currentScale * scaleStep).clamp(
      _minScaleFactor,
      _maxScaleFactor,
    );

    // Create a new transformation
    final newMatrix = Matrix4.identity()
      ..translate(scenePointBefore.dx, scenePointBefore.dy)
      ..scale(newScale / currentScale)
      ..translate(-scenePointBefore.dx, -scenePointBefore.dy);

    // Apply the new transformation
    controller.value = newMatrix * controller.value;

    // Convert the center point to scene coordinates after scaling
    final scenePointAfter = controller.toScene(center);

    // Compute difference to keep the same center point
    final dx = scenePointAfter.dx - scenePointBefore.dx;
    final dy = scenePointAfter.dy - scenePointBefore.dy;

    // Apply the translation
    controller.value = Matrix4.identity()
      ..translate(-dx, -dy)
      ..multiply(controller.value);

    _onControllerChanged();
  }
}

void openInteractiveViewerFromFile(
  BuildContext context,
  MediaFilePB file, {
  required void Function(int) onDeleteImage,
  UserProfilePB? userProfile,
  MediaActionService actions = const MediaActionService(),
}) =>
    showDialog(
      context: context,
      builder: (_) => InteractiveImageViewer(
        userProfile: userProfile,
        actions: actions,
        imageProvider: MediaFileImageProvider(
          files: [file],
          initialFileId: file.id,
          onDeleteImage: onDeleteImage,
        ),
      ),
    );

void openInteractiveViewerFromFiles(
  BuildContext context,
  List<MediaFilePB> files, {
  required void Function(int) onDeleteImage,
  int initialIndex = 0,
  UserProfilePB? userProfile,
  MediaActionService actions = const MediaActionService(),
}) =>
    showDialog(
      context: context,
      builder: (_) => InteractiveImageViewer(
        userProfile: userProfile,
        actions: actions,
        imageProvider: MediaFileImageProvider(
          initialFileId: files.isEmpty
              ? null
              : files[initialIndex.clamp(0, files.length - 1)].id,
          files: files,
          onDeleteImage: onDeleteImage,
        ),
      ),
    );
