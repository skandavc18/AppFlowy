import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_gallery_labels.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_library_page.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

/// The shell plugin type that shows [library].
PluginType viewLibraryPluginType(ViewLibrary library) => switch (library) {
      ViewLibrary.recents => PluginType.recents,
      ViewLibrary.favorites => PluginType.favorites,
      ViewLibrary.all => PluginType.pageLibrary,
    };

/// Recents, Favorites and the Library are places in the shell, like Trash and
/// Templates: never created as pages, never stored in the folder tree.
class ViewLibraryPluginBuilder extends PluginBuilder {
  ViewLibraryPluginBuilder(this.library);

  final ViewLibrary library;

  @override
  Plugin build(dynamic data) => ViewLibraryPlugin(library);

  @override
  String get menuName => switch (library) {
        ViewLibrary.recents => 'Recents',
        ViewLibrary.favorites => 'Favorites',
        ViewLibrary.all => 'Library',
      };

  @override
  FlowySvgData get icon => switch (library) {
        ViewLibrary.recents => FlowySvgs.time_s,
        ViewLibrary.favorites => FlowySvgs.star_s,
        ViewLibrary.all => FlowySvgs.icon_document_s,
      };

  @override
  PluginType get pluginType => viewLibraryPluginType(library);

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class ViewLibraryPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class ViewLibraryPlugin extends Plugin {
  ViewLibraryPlugin(this.library);

  final ViewLibrary library;

  @override
  PluginWidgetBuilder get widgetBuilder => ViewLibraryPluginDisplay(library);

  @override
  PluginId get id => switch (library) {
        ViewLibrary.recents => 'RecentsStack',
        ViewLibrary.favorites => 'FavoritesStack',
        ViewLibrary.all => 'LibraryStack',
      };

  @override
  PluginType get pluginType => viewLibraryPluginType(library);
}

class ViewLibraryPluginDisplay extends PluginWidgetBuilder {
  ViewLibraryPluginDisplay(this.library);

  final ViewLibrary library;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  String? get viewName => viewLibraryTitle(library);

  @override
  Widget get leftBarItem => FlowyText.medium(viewLibraryTitle(library));

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;

  @override
  Widget? get rightBarItem => null;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      ViewLibraryPage(
        key: ValueKey('view-library-${library.name}'),
        library: library,
        userProfile: context.userProfile,
      );

  @override
  List<NavigationItem> get navigationItems => [this];
}
