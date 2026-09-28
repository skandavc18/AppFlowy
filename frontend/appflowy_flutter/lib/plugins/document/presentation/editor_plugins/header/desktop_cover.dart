import 'package:flutter/material.dart';

import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:string_validator/string_validator.dart';

/// This is a transitional component that can be removed once the desktop
///  supports immersive widgets, allowing for the exclusive use of the DocumentImmersiveCover component.
class DesktopCover extends StatefulWidget {
  const DesktopCover({
    super.key,
    required this.view,
    required this.editorState,
    required this.node,
    required this.coverType,
    this.coverDetails,
  });

  final ViewPB view;
  final Node node;
  final EditorState editorState;
  final CoverType coverType;
  final String? coverDetails;

  @override
  State<DesktopCover> createState() => _DesktopCoverState();
}

class _DesktopCoverState extends State<DesktopCover> {
  CoverType get coverType => CoverType.fromString(
        widget.node.attributes[DocumentHeaderBlockKeys.coverType],
      );
  String? get coverDetails =>
      widget.node.attributes[DocumentHeaderBlockKeys.coverDetails];

  @override
  Widget build(BuildContext context) {
    if (widget.view.cover == null) {
      return _buildCoverImageV1();
    }

    return _buildCoverImageV2();
  }

  // version > 0.5.5
  Widget _buildCoverImageV2() {
    final cover = widget.view.cover!;
    if (cover.isNone) return const SizedBox.shrink();
    // DocumentCoverWidget owns the view subscription. A second async fetch
    // here can briefly restore an older image after a target/cover change.
    return ViewCoverImage(
      cover: cover,
      userProfile: context.read<DocumentBloc?>()?.state.userProfilePB,
      width: double.infinity,
      height: double.infinity,
    );
  }

  // version <= 0.5.5
  Widget _buildCoverImageV1() {
    final presentation = PageCoverPresentation.maybeOf(context);
    final fit = presentation?.appearance.boxFit ?? BoxFit.cover;
    final alignment = presentation?.alignment ?? Alignment.center;
    final detail = coverDetails;
    if (detail == null) {
      return const SizedBox.shrink();
    }
    switch (widget.coverType) {
      case CoverType.file:
        return ViewCoverImage(
          cover: PageStyleCover(
            type: isURL(detail)
                ? PageStyleCoverImageType.customImage
                : PageStyleCoverImageType.localImage,
            value: detail,
          ),
          userProfile: context.read<DocumentBloc?>()?.state.userProfilePB,
          fit: fit,
          alignment: alignment,
          fallback: const SizedBox.shrink(),
        );
      case CoverType.asset:
        return ViewCoverImage(
          cover: PageStyleCover(
              type: PageStyleCoverImageType.builtInImage, value: detail),
          fit: fit,
          alignment: alignment,
          fallback: const SizedBox.shrink(),
        );
      case CoverType.color:
        final color = widget.coverDetails?.tryToColor() ??
            Theme.of(context).colorScheme.surface;
        return Container(color: color);
      case CoverType.none:
        return const SizedBox.shrink();
    }
  }
}
