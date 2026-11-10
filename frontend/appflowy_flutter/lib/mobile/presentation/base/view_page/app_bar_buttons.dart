import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/base/mobile_view_page_bloc.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/app_bar.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/app_bar_actions.dart';
import 'package:appflowy/mobile/presentation/base/view_page/more_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/cover/cover_ink.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_style/page_style_bottom_sheet.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/view/prelude.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class MobileViewPageImmersiveAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const MobileViewPageImmersiveAppBar({
    super.key,
    required this.preferredSize,
    required this.appBarOpacity,
    required this.title,
    required this.actions,
    required this.view,
  });

  final ValueListenable appBarOpacity;
  final Widget title;
  final List<Widget> actions;
  final ViewPB? view;
  @override
  final Size preferredSize;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appBarOpacity,
      builder: (_, opacity, __) => FlowyAppBar(
        backgroundColor:
            AppBarTheme.of(context).backgroundColor?.withValues(alpha: opacity),
        showDivider: false,
        title: _buildTitle(context, opacity: opacity),
        leadingWidth: 44,
        leading: Padding(
          padding: const EdgeInsets.only(top: 4.0, bottom: 4.0, left: 12.0),
          child: _buildAppBarBackButton(context),
        ),
        actions: actions,
      ),
    );
  }

  Widget _buildTitle(
    BuildContext context, {
    required double opacity,
  }) {
    return title;
  }

  Widget _buildAppBarBackButton(BuildContext context) {
    return AppBarButton(
      padding: EdgeInsets.zero,
      onTap: (context) => context.pop(),
      child: _ImmersiveAppBarButton(
        icon: FlowySvgs.m_app_bar_back_s,
        dimension: 30.0,
        iconPadding: 3.0,
        cover: view?.cover,
        appBarOpacity: appBarOpacity,
      ),
    );
  }
}

class MobileViewPageMoreButton extends StatelessWidget {
  const MobileViewPageMoreButton({
    super.key,
    required this.view,
    required this.appBarOpacity,
  });

  final ViewPB view;
  final ValueListenable appBarOpacity;

  @override
  Widget build(BuildContext context) {
    return AppBarButton(
      padding: const EdgeInsets.only(left: 8, right: 16),
      onTap: (context) {
        EditorNotification.exitEditing().post();

        showMobileBottomSheet(
          context,
          showDragHandle: true,
          showDivider: false,
          backgroundColor: AFThemeExtension.of(context).background,
          builder: (_) => MultiBlocProvider(
            providers: [
              BlocProvider.value(value: context.read<ViewBloc>()),
              BlocProvider.value(value: context.read<FavoriteBloc>()),
              BlocProvider.value(value: context.read<MobileViewPageBloc>()),
              BlocProvider.value(value: context.read<ShareBloc>()),
              BlocProvider.value(value: context.read<PageAccessLevelBloc>()),
            ],
            child: MobileViewPageMoreBottomSheet(view: view),
          ),
        );
      },
      child: _ImmersiveAppBarButton(
        icon: FlowySvgs.m_app_bar_more_s,
        dimension: 30.0,
        iconPadding: 3.0,
        cover: view.cover,
        appBarOpacity: appBarOpacity,
      ),
    );
  }
}

class MobileViewPageLayoutButton extends StatelessWidget {
  const MobileViewPageLayoutButton({
    super.key,
    required this.view,
    required this.appBarOpacity,
    required this.tabs,
  });

  final ViewPB view;
  final List<PickerTabType> tabs;
  final ValueListenable appBarOpacity;

  @override
  Widget build(BuildContext context) {
    // only display the layout button if the view is a document
    if (view.layout != ViewLayoutPB.Document) {
      return const SizedBox.shrink();
    }

    return AppBarButton(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      onTap: (context) {
        EditorNotification.exitEditing().post();

        showMobileBottomSheet(
          context,
          showDragHandle: true,
          showDivider: false,
          showDoneButton: true,
          showHeader: true,
          title: LocaleKeys.pageStyle_title.tr(),
          backgroundColor: AFThemeExtension.of(context).background,
          builder: (_) => MultiBlocProvider(
            providers: [
              BlocProvider.value(value: context.read<DocumentPageStyleBloc>()),
              BlocProvider.value(value: context.read<MobileViewPageBloc>()),
            ],
            child: PageStyleBottomSheet(
              view: context.read<ViewBloc>().state.view,
              tabs: tabs,
            ),
          ),
        );
      },
      child: _ImmersiveAppBarButton(
        icon: FlowySvgs.m_layout_s,
        dimension: 30.0,
        iconPadding: 3.0,
        cover: view.cover,
        appBarOpacity: appBarOpacity,
      ),
    );
  }
}

class _ImmersiveAppBarButton extends StatelessWidget {
  const _ImmersiveAppBarButton({
    required this.icon,
    required this.dimension,
    required this.iconPadding,
    required this.cover,
    required this.appBarOpacity,
  });

  final FlowySvgData icon;
  final double dimension;
  final double iconPadding;
  final PageStyleCover? cover;
  final ValueListenable appBarOpacity;

  @override
  Widget build(BuildContext context) {
    assert(
      dimension > 0.0 && dimension <= kToolbarHeight,
      'dimension must be greater than 0, and less than or equal to kToolbarHeight',
    );

    return UnconstrainedBox(
      child: SizedBox.square(
        dimension: dimension,
        child: ValueListenableBuilder(
          valueListenable: appBarOpacity,
          builder: (context, appBarOpacity, child) {
            // While the bar is see-through the glyph sits on the cover, so it
            // takes the cover's ink on a disc of the opposite tone; on the
            // bar, or with no cover, it keeps the theme's.
            final onCover =
                appBarOpacity < 0.99 ? CoverInk.button(context, cover) : null;

            Widget child = Container(
              margin: EdgeInsets.all(iconPadding),
              child: FlowySvg(icon, color: onCover?.ink),
            );

            if (onCover != null) {
              child = DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(dimension / 2.0),
                  color: onCover.disc,
                ),
                child: child,
              );
            }

            return child;
          },
        ),
      ),
    );
  }
}
