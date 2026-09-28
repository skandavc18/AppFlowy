import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
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
    this.ocrService,
    this.ocrSourceBuilder,
    this.canReadImage,
    this.onEditImage,
  });

  final UserProfilePB? userProfile;
  final AFImageProvider imageProvider;
  final MediaActionService actions;
  final OcrService? ocrService;
  final ImageOcrSourceBuilder? ocrSourceBuilder;
  final bool Function()? canReadImage;
  final Future<void> Function()? onEditImage;

  @override
  State<InteractiveImageViewer> createState() => _InteractiveImageViewerState();
}

class _InteractiveImageViewerState extends State<InteractiveImageViewer>
    with SingleTickerProviderStateMixin {
  final TransformationController controller = TransformationController();
  final focusNode = FocusNode();
  late MediaActionService _guardedActions;
  AnimationController? _fitAnimation;
  Matrix4Tween? _fitTween;
  int _gestureRevision = 0;
  int _imageRevision = 0;

  void _bindActions() {
    final delegate = widget.actions;
    _guardedActions = _ViewerMediaActions(
      delegate: delegate,
      canRead: (source) =>
          _canReadImage &&
          delegate == widget.actions &&
          ModalRoute.of(context)?.isCurrent != false &&
          source.source == MediaActionSource.image(currentImage).source &&
          source.name == widget.imageProvider.getImageName(currentIndex),
    );
  }

  void _fitToView() {
    if (!_canReadImage || ModalRoute.of(context)?.isCurrent == false) return;
    _fitAnimation?.stop();
    // Cancel InteractiveViewer's private inertia, keeping our controller and
    // decoded image cache. The same reset behavior is used by workspace photos.
    setState(() => _gestureRevision++);
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      controller.value = Matrix4.identity();
      return;
    }
    _fitTween =
        Matrix4Tween(begin: controller.value.clone(), end: Matrix4.identity());
    _fitAnimation ??= (AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200))
      ..addListener(() {
        controller.value = _fitTween!
            .transform(Curves.easeOutCubic.transform(_fitAnimation!.value));
      }));
    unawaited(_fitAnimation!.forward(from: 0));
  }

  Future<void> _editImage() async {
    if (!_canReadImage || ModalRoute.of(context)?.isCurrent == false) return;
    final provider = widget.imageProvider;
    final index = currentIndex;
    await widget.onEditImage?.call();
    if (_canReadImage &&
        identical(provider, widget.imageProvider) &&
        index == currentIndex) {
      setState(() => _imageRevision++);
    }
  }

  int currentScale = 100;
  late int currentIndex = widget.imageProvider.initialIndex;

  bool get isLastIndex => currentIndex == widget.imageProvider.imageCount - 1;
  bool get isFirstIndex => currentIndex == 0;

  ImageBlockData get currentImage =>
      widget.imageProvider.getImage(currentIndex);

  bool get _canReadImage =>
      mounted &&
      (widget.canReadImage?.call() ?? true) &&
      currentIndex >= 0 &&
      currentIndex < widget.imageProvider.imageCount;

  ImageEditorSource _ocrSource(UserProfilePB? profile) {
    final image = currentImage;
    final uri = Uri.tryParse(image.url);
    return widget.ocrSourceBuilder?.call(image) ??
        ImageEditorSource(
          url: image.type == CustomImageType.local &&
                  uri?.isScheme('file') == true
              ? File.fromUri(uri!).path
              : image.url,
          type: image.type,
          userProfile: image.type == CustomImageType.internal ? profile : null,
        );
  }

  void _closeViewer() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true && route!.navigator!.canPop()) {
      route.navigator!.pop();
    }
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    _clampIndex();
    _bindActions();
  }

  @override
  void didUpdateWidget(covariant InteractiveImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _clampIndex();
    if (oldWidget.actions != widget.actions) _bindActions();
  }

  void _clampIndex() {
    currentIndex = widget.imageProvider.imageCount == 0
        ? 0
        : currentIndex.clamp(0, widget.imageProvider.imageCount - 1);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final scale = controller.value.getMaxScaleOnAxis();
    final percentage = (scale * 100).toInt();
    if (percentage != currentScale) setState(() => currentScale = percentage);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    _fitAnimation?.dispose();
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    final image = widget.imageProvider.imageCount > 0 ? currentImage : null;
    final provider = widget.imageProvider;

    return ContextualFindScope(
      child: Material(
        color: DocumentViewportStyle.of(context).canvas,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Focus(
              focusNode: focusNode,
              autofocus: true,
              onKeyEvent: (_, event) => _handleKey(event, _canvasSize),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.imageProvider.imageCount > 0)
                    InteractiveImageToolbar(
                      currentImage: currentImage,
                      imageName:
                          widget.imageProvider.getImageName(currentIndex),
                      imageCount: widget.imageProvider.imageCount,
                      isFirstIndex: isFirstIndex,
                      isLastIndex: isLastIndex,
                      currentScale: currentScale,
                      userProfile: userProfile,
                      actions: _guardedActions,
                      enabled: _canReadImage,
                      canRead: () =>
                          _canReadImage &&
                          identical(provider, widget.imageProvider) &&
                          currentImage.url == image?.url &&
                          currentImage.type == image?.type,
                      onClose: _closeViewer,
                      onFit: _fitToView,
                      onEdit: widget.onEditImage == null
                          ? null
                          : () => unawaited(_editImage()),
                      onExtractText: () {
                        if (!_canReadImage ||
                            ModalRoute.of(context)?.isCurrent == false) return;
                        unawaited(showImageOcrOverlay(
                          context,
                          source: _ocrSource(userProfile),
                          name: widget.imageProvider.getImageName(currentIndex),
                          service: widget.ocrService,
                        ));
                      },
                      onPrevious: () => _move(-1),
                      onNext: () => _move(1),
                      onZoomIn: () => _zoom(1.1, _canvasSize),
                      onZoomOut: () => _zoom(.9, _canvasSize),
                      onScaleChanged: (scale) {
                        if (!_canReadImage) return;
                        final currentScale =
                            controller.value.getMaxScaleOnAxis();
                        final scaleStep = scale / currentScale;
                        _zoom(scaleStep, _canvasSize, fromOwnedMenu: true);
                      },
                      onDelete: widget.imageProvider.onDeleteImage == null
                          ? null
                          : () {
                              if (_canReadImage &&
                                  ModalRoute.of(context)?.isCurrent != false) {
                                widget.imageProvider.onDeleteImage
                                    ?.call(currentIndex);
                              }
                            },
                    )
                  else
                    Align(
                      alignment: Alignment.topRight,
                      child: WorkspaceControlButton(
                        key: const ValueKey('photo-fullscreen-close'),
                        icon: Icons.close_rounded,
                        tooltip: 'Exit full screen (Esc)',
                        onPressed: _closeViewer,
                      ),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, canvas) {
                        _canvasSize = canvas.biggest;
                        return ClipRect(
                          child: InteractiveViewer(
                            key: ValueKey(_gestureRevision),
                            onInteractionStart: (_) => _fitAnimation?.stop(),
                            boundaryMargin:
                                const EdgeInsets.all(double.infinity),
                            transformationController: controller,
                            constrained: false,
                            minScale: _minScaleFactor,
                            maxScale: _maxScaleFactor,
                            scaleFactor: 500,
                            child: SizedBox(
                              width: canvas.maxWidth,
                              height: canvas.maxHeight,
                              child: widget.imageProvider.imageCount == 0
                                  ? const SizedBox.shrink()
                                  : GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onDoubleTap: _closeViewer,
                                      child: ImageOcrFindRegion(
                                        source: _ocrSource(userProfile),
                                        name: widget.imageProvider
                                            .getImageName(currentIndex),
                                        service: widget.ocrService,
                                        isAvailable: () => _canReadImage,
                                        isSelected: () => _canReadImage,
                                        debugLabel: 'Photo viewer image',
                                        child: KeyedSubtree(
                                          key: ValueKey(_imageRevision),
                                          child:
                                              widget.imageProvider.renderImage(
                                            context,
                                            currentIndex,
                                            userProfile,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Size _canvasSize = Size.zero;

  KeyEventResult _handleKey(KeyEvent event, Size size) {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
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
        _closeViewer();
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
      _fitToView();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _move(int steps) {
    if (!_canReadImage || ModalRoute.of(context)?.isCurrent == false) return;
    setState(() {
      final index = currentIndex + steps;
      currentIndex = index.clamp(0, widget.imageProvider.imageCount - 1);
    });
  }

  void _zoom(double scaleStep, Size size, {bool fromOwnedMenu = false}) {
    if (!_canReadImage ||
        !scaleStep.isFinite ||
        scaleStep <= 0 ||
        (!fromOwnedMenu && ModalRoute.of(context)?.isCurrent == false)) {
      return;
    }
    _fitAnimation?.stop();
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

class _ViewerMediaActions extends MediaActionService {
  const _ViewerMediaActions({required this.delegate, required this.canRead});

  final MediaActionService delegate;
  final bool Function(MediaActionSource) canRead;

  @override
  Future<void> copy(MediaActionSource source) async {
    if (!canRead(source)) throw StateError('Image unavailable');
    await delegate.copy(source);
    if (!canRead(source)) throw StateError('Image unavailable');
  }

  @override
  Future<void> share(MediaActionSource source,
      {Rect? sharePositionOrigin}) async {
    if (!canRead(source)) throw StateError('Image unavailable');
    await delegate.share(source, sharePositionOrigin: sharePositionOrigin);
    if (!canRead(source)) throw StateError('Image unavailable');
  }
}

/// Opens the existing photo renderer with the same restrained transition as
/// fullscreen PDFs. The route owns no image/controller resources itself.
Future<void> showInteractiveImageViewer(
  BuildContext context, {
  required InteractiveImageViewer viewer,
}) {
  final reduced = MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.68),
    transitionDuration:
        reduced ? Duration.zero : const Duration(milliseconds: 200),
    transitionBuilder: (_, animation, __, child) => reduced
        ? child
        : FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
            child: ScaleTransition(
              scale: Tween(begin: 0.985, end: 1.0).animate(animation),
              child: child,
            ),
          ),
    pageBuilder: (_, __, ___) => themes.wrap(viewer),
  );
}

void openInteractiveViewerFromFile(
  BuildContext context,
  MediaFilePB file, {
  required void Function(int) onDeleteImage,
  UserProfilePB? userProfile,
  MediaActionService actions = const MediaActionService(),
}) =>
    showInteractiveImageViewer(
      context,
      viewer: InteractiveImageViewer(
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
    showInteractiveImageViewer(
      context,
      viewer: InteractiveImageViewer(
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
