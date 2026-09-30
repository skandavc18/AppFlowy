import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// Home's cover with the search bar laid across its lower edge: half on the
/// picture, half on the page. The bar stays centred on that edge as the cover
/// is resized, its picture changes, or the pane gets narrower.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.search,
    required this.inset,
    this.cover,
    this.coverActions,
    this.addCover,
    this.coverView,
    this.coverBackend,
    this.below,
  });

  static const searchMaxWidth = 760.0;

  final Widget search;
  final double inset;

  /// The cover picture; null when the workspace has none.
  final Widget? cover;
  final Widget? coverActions;

  /// Offered where the cover would be, when there is none.
  final Widget? addCover;

  /// Where the cover's height is kept; null leaves it at its default.
  final ViewPB? coverView;
  final PageCoverBackendService? coverBackend;

  /// Centred under the search bar.
  final Widget? below;

  Widget _measure(Widget child) => Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: searchMaxWidth),
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : WorkspaceTokens.pageMaxWidth;
          final bar = _measure(search);
          final after = below == null ? null : _measure(below!);
          final image = cover;
          if (image == null) {
            return PreviewToolbarRegion(
              child: Padding(
                key: const ValueKey('home-hero'),
                padding: const EdgeInsets.only(top: WorkspaceTokens.space12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (addCover != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: WorkspaceTokens.space3,
                        ),
                        child: _measure(
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: addCover,
                          ),
                        ),
                      ),
                    bar,
                    if (after != null) ...[
                      const SizedBox(height: WorkspaceTokens.space4),
                      after,
                    ],
                  ],
                ),
              ),
            );
          }
          // The grip and cover tools sit clear of the bar's upper half.
          final clearance = MediaQuery.textScalerOf(context).scale(28) +
              WorkspaceTokens.space1;
          return PageCoverLayout(
            width: (width - WorkspaceTokens.coverInset * 2)
                .clamp(0.0, double.infinity)
                .toDouble(),
            fallbackHeight: width < 600 ? 180 : 232,
            view: coverView,
            editable: coverView != null,
            backend: coverBackend,
            builder: (context, height, grip) => PreviewToolbarRegion(
              child: Column(
                key: const ValueKey('home-hero'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WorkspaceTokens.coverInset,
                      WorkspaceTokens.space2,
                      WorkspaceTokens.coverInset,
                      0,
                    ),
                    child: SizedBox(
                      key: const ValueKey('home-cover'),
                      height: height,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          PageCoverPresentation.maybeOf(context)!
                              .appearance
                              .radius,
                        ),
                        child: WorkspacePageCover(
                          image: image,
                          actions: coverActions,
                          resizeGrip: grip,
                          bottomInset: clearance,
                        ),
                      ),
                    ),
                  ),
                  // Half of the bar lies on the picture: it is centred on the
                  // cover's lower edge whatever height either of them has.
                  FractionalTranslation(
                    key: const ValueKey('home-search-dock'),
                    translation: const Offset(0, -0.5),
                    child: bar,
                  ),
                  if (after != null) after,
                ],
              ),
            ),
          );
        },
      );
}
