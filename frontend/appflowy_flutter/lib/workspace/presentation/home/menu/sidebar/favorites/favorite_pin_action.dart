import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FavoritePinAction extends StatelessWidget {
  const FavoritePinAction({super.key, required this.view});

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    final tooltip = view.isPinned
        ? LocaleKeys.favorite_removeFromSidebar.tr()
        : LocaleKeys.favorite_addToSidebar.tr();
    return FlowyTooltip(
      message: tooltip,
      child: SidebarIconButton(
        icon: SidebarIcon.pin,
        onPressed: () {
          view.isPinned
              ? context.read<FavoriteBloc>().add(FavoriteEvent.unpin(view))
              : context.read<FavoriteBloc>().add(FavoriteEvent.pin(view));
        },
      ),
    );
  }
}
