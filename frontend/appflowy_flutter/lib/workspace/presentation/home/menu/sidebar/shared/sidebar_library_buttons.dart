import 'package:appflowy/plugins/view_library/view_library_plugin.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_gallery_labels.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Recents, Favorites or the Library, directly under Home. Opening one never
/// creates a page, reorders the tree or writes the latest-view preference.
class SidebarLibraryButton extends StatelessWidget {
  const SidebarLibraryButton({super.key, required this.library});

  final ViewLibrary library;

  @override
  Widget build(BuildContext context) {
    final type = viewLibraryPluginType(library);
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) => SidebarNavItem(
        key: ValueKey(
          library == ViewLibrary.all
              ? 'sidebar-library'
              : 'sidebar-${library.name}',
        ),
        icon: switch (library) {
          ViewLibrary.recents => SidebarIcon.recents,
          ViewLibrary.favorites => SidebarIcon.favorites,
          ViewLibrary.all => SidebarIcon.pageLibrary,
        },
        label: viewLibraryTitle(library),
        selected: state.currentPageManager.plugin.pluginType == type,
        onTap: () {
          final tabs = context.read<TabsBloc>();
          if (tabs.isClosed) return;
          if (getIt.isRegistered<MenuSharedState>()) {
            getIt<MenuSharedState>().latestOpenView = null;
          }
          tabs.add(
            TabsEvent.openPlugin(
              plugin: makePlugin(pluginType: type),
              setLatest: false,
            ),
          );
        },
      ),
    );
  }
}
