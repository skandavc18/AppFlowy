import 'package:flutter/material.dart';

import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/image_render.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/layouts/multi_image_layouts.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:collection/collection.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

class ImageGridLayout extends ImageBlockMultiLayout {
  const ImageGridLayout({
    super.key,
    required super.node,
    required super.editorState,
    required super.images,
    required super.indexNotifier,
    required super.isLocalMode,
    this.mediaActions = const MediaActionService(),
  });

  final MediaActionService mediaActions;

  @override
  State<ImageGridLayout> createState() => _ImageGridLayoutState();
}

class _ImageGridLayoutState extends State<ImageGridLayout> {
  @override
  Widget build(BuildContext context) {
    return StaggeredGridBuilder(
      images: widget.images,
      mediaActions: widget.mediaActions,
      onImageDoubleTapped: (index) {
        _openInteractiveViewer(context, index);
      },
    );
  }

  void _openInteractiveViewer(BuildContext context, int index) => showDialog(
        context: context,
        builder: (_) => InteractiveImageViewer(
          userProfile: context.read<DocumentBloc?>()?.state.userProfilePB,
          actions: widget.mediaActions,
          imageProvider: AFBlockImageProvider(
            images: widget.images,
            initialIndex: index,
            onDeleteImage: widget.editorState.editable
                ? (index) async {
                    // Permissions can change while the viewer is still open.
                    if (!widget.editorState.editable) {
                      return;
                    }
                    final transaction = widget.editorState.transaction;
                    final newImages = widget.images.toList();
                    newImages.removeAt(index);

                    if (newImages.isNotEmpty) {
                      transaction.updateNode(
                        widget.node,
                        {
                          MultiImageBlockKeys.images:
                              newImages.map((e) => e.toJson()).toList(),
                          MultiImageBlockKeys.layout: widget
                              .node.attributes[MultiImageBlockKeys.layout],
                        },
                      );
                    } else {
                      transaction.deleteNode(widget.node);
                    }

                    await widget.editorState.apply(transaction);
                  }
                : null,
          ),
        ),
      );
}

/// Draws a staggered grid of images, where the pattern is based
/// on the amount of images to fill the grid at all times.
///
/// They will be alternating depending on the current index of the images, such that
/// the layout is reversed in odd segments.
///
/// If there are 4 images in the last segment, this layout will be used:
/// ┌─────┐┌─┐┌─┐
/// │     │└─┘└─┘
/// │     │┌────┐
/// └─────┘└────┘
///
/// If there are 3 images in the last segment, this layout will be used:
/// ┌─────┐┌────┐
/// │     │└────┘
/// │     │┌────┐
/// └─────┘└────┘
///
/// If there are 2 images in the last segment, this layout will be used:
/// ┌─────┐┌─────┐
/// │     ││     │
/// └─────┘└─────┘
///
/// If there is 1 image in the last segment, this layout will be used:
/// ┌──────────┐
/// │          │
/// └──────────┘
class StaggeredGridBuilder extends StatelessWidget {
  const StaggeredGridBuilder({
    super.key,
    required this.images,
    required this.onImageDoubleTapped,
    this.mediaActions = const MediaActionService(),
  });

  final List<ImageBlockData> images;
  final void Function(int) onImageDoubleTapped;
  final MediaActionService mediaActions;

  @override
  Widget build(BuildContext context) {
    final userProfile = context.select<DocumentBloc?, UserProfilePB?>(
      (bloc) => bloc?.state.userProfilePB,
    );
    return StaggeredGrid.count(
      crossAxisCount: 4,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: _buildTiles(userProfile).toList(),
    );
  }

  Iterable<Widget> _buildTiles(UserProfilePB? userProfile) sync* {
    // Recompute from the current list even when a replacement/reorder keeps its
    // length. Keys follow photos, not the browser's selected index or grid slot.
    final occurrences = <(String, CustomImageType, String?), int>{};
    for (final (segment, group) in images.slices(4).indexed) {
      final reversed = segment.isOdd;
      final dimensions = switch (group.length) {
        4 => [
            (reversed ? 1 : 2, reversed ? 1 : 2),
            (1, 1),
            (reversed ? 2 : 1, reversed ? 2 : 1),
            (2, 1),
          ],
        3 => [(2, reversed ? 1 : 2), (2, reversed ? 2 : 1), (2, 1)],
        2 => const [(2, 2), (2, 2)],
        _ => const [(4, 2)],
      };
      for (final (offset, image) in group.indexed) {
        final identity = (image.url, image.type, image.workspaceFileId);
        final occurrence = occurrences.update(
          identity,
          (count) => count + 1,
          ifAbsent: () => 0,
        );
        final imageIndex = segment * 4 + offset;
        yield StaggeredGridTile.count(
          key: ValueKey((identity, occurrence)),
          crossAxisCellCount: dimensions[offset].$1,
          mainAxisCellCount: dimensions[offset].$2,
          child: MediaHoverRegion(
            builder: (context, visible) => Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onDoubleTap: () => onImageDoubleTapped(imageIndex),
                  child: ImageRender(
                    image: image,
                    userProfile: image.type == CustomImageType.external
                        ? null
                        : userProfile,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                // Keep clear of the gallery's top toolbar. Only the photo is
                // clipped; the shared feedback badge can paint above this bar.
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 72),
                      child: MediaActionReveal(
                        visible: visible,
                        child: MediaActionButtons(
                          key: ValueKey(
                            ('grid-image-actions', identity, occurrence),
                          ),
                          source: MediaActionSource.image(
                            image,
                            userProfile: userProfile,
                          ),
                          actions: mediaActions,
                          buttonSize: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }
}
