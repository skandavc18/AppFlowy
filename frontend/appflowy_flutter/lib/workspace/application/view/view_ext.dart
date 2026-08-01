import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart'
    show PageStyleFontLayout, PageStyleLineHeightLayout;
import 'package:appflowy/plugins/ai_chat/chat.dart';
import 'package:appflowy/plugins/collection/bookmark_plugin.dart';
import 'package:appflowy/plugins/collection/collection_plugin.dart';
import 'package:appflowy/plugins/database/board/presentation/board_page.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_page.dart';
import 'package:appflowy/plugins/database/grid/presentation/grid_page.dart';
import 'package:appflowy/plugins/database/grid/presentation/mobile_grid_page.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/plugins/workspace_folder/workspace_folder_plugin.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_plugin.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class PluginArgumentKeys {
  static String selection = "selection";
  static String rowId = "row_id";
  static String blockId = "block_id";
}

class ViewExtKeys {
  // used for customizing the font family.
  static String fontKey = 'font';

  // used for customizing the font layout.
  static String fontLayoutKey = 'font_layout';

  // used for customizing the line height layout.
  static String lineHeightLayoutKey = 'line_height_layout';

  // cover keys
  static String coverKey = ViewCoverCodec.coverKey;
  static String coverTypeKey = ViewCoverCodec.coverTypeKey;
  static String coverValueKey = ViewCoverCodec.coverValueKey;

  // is pinned
  static String isPinnedKey = 'is_pinned';

  // space
  static String isSpaceKey = 'is_space';
  static String spaceCreatorKey = 'space_creator';
  static String spaceCreatedAtKey = 'space_created_at';
  static String spaceIconKey = 'space_icon';
  static String spaceIconColorKey = 'space_icon_color';
  static String spacePermissionKey = 'space_permission';
}

extension MinimalViewExtension on FolderViewMinimalPB {
  Widget defaultIcon({Size? size}) => FlowySvg(
        switch (layout) {
          ViewLayoutPB.Board => FlowySvgs.icon_board_s,
          ViewLayoutPB.Calendar => FlowySvgs.icon_calendar_s,
          ViewLayoutPB.Grid => FlowySvgs.icon_grid_s,
          ViewLayoutPB.Document => FlowySvgs.icon_document_s,
          ViewLayoutPB.Chat => FlowySvgs.chat_ai_page_s,
          _ => FlowySvgs.icon_document_s,
        },
        size: size,
      );
}

extension ViewExtension on ViewPB {
  String get nameOrDefault =>
      name.isEmpty ? LocaleKeys.menuAppHeader_defaultNewPageName.tr() : name;

  bool get isDocument => pluginType == PluginType.document;
  bool get isDatabase => [
        PluginType.grid,
        PluginType.board,
        PluginType.calendar,
      ].contains(pluginType);

  Widget defaultIcon({Size? size}) {
    if (isWorkspaceItem) {
      return WorkspaceItemIcon.fromView(
        view: this,
        size: size?.width ?? 16,
      );
    }
    return FlowySvg(
      switch (layout) {
        ViewLayoutPB.Board => FlowySvgs.icon_board_s,
        ViewLayoutPB.Calendar => FlowySvgs.icon_calendar_s,
        ViewLayoutPB.Grid => FlowySvgs.icon_grid_s,
        ViewLayoutPB.Document => FlowySvgs.icon_document_s,
        ViewLayoutPB.Chat => FlowySvgs.chat_ai_page_s,
        _ => FlowySvgs.icon_document_s,
      },
      size: size,
    );
  }

  PluginType get pluginType => switch (layout) {
        ViewLayoutPB.Board => PluginType.board,
        ViewLayoutPB.Calendar => PluginType.calendar,
        ViewLayoutPB.Document => PluginType.document,
        ViewLayoutPB.Grid => PluginType.grid,
        ViewLayoutPB.Chat => PluginType.chat,
        _ => throw UnimplementedError(),
      };

  Plugin plugin({
    Map<String, dynamic> arguments = const {},
  }) {
    // A collection is a workspace folder with a purpose, so it must be matched
    // before the plain folder it also declares itself to be.
    if (isCollection) {
      return CollectionPlugin(view: this);
    }
    if (isWorkspaceFolder) {
      return WorkspaceFolderPlugin(view: this);
    }
    // A saved link is a workspace file with no bytes of its own, so it opens
    // in the bookmark reader rather than in the file viewer.
    if (isBookmark) {
      return BookmarkPlugin(view: this);
    }
    // Workspace files open in their own viewer instead of a document page that
    // just embeds them. Older files without stored bytes migrate on open.
    if (isWorkspaceFile) {
      return WorkspaceFilePlugin(view: this);
    }
    switch (layout) {
      case ViewLayoutPB.Board:
      case ViewLayoutPB.Calendar:
      case ViewLayoutPB.Grid:
        final String? rowId = arguments[PluginArgumentKeys.rowId];

        return DatabaseTabBarViewPlugin(
          view: this,
          pluginType: pluginType,
          initialRowId: rowId,
        );
      case ViewLayoutPB.Document:
        final selectionValue = arguments[PluginArgumentKeys.selection];
        Selection? initialSelection;
        if (selectionValue is Selection) initialSelection = selectionValue;

        final String? initialBlockId = arguments[PluginArgumentKeys.blockId];

        return DocumentPlugin(
          view: this,
          pluginType: pluginType,
          initialSelection: initialSelection,
          initialBlockId: initialBlockId,
        );
      case ViewLayoutPB.Chat:
        return AIChatPagePlugin(view: this);
    }
    throw UnimplementedError;
  }

  DatabaseTabBarItemBuilder tabBarItem() => switch (layout) {
        ViewLayoutPB.Board => BoardPageTabBarBuilderImpl(),
        ViewLayoutPB.Calendar => CalendarPageTabBarBuilderImpl(),
        ViewLayoutPB.Grid => DesktopGridTabBarBuilderImpl(),
        _ => throw UnimplementedError,
      };

  DatabaseTabBarItemBuilder mobileTabBarItem() => switch (layout) {
        ViewLayoutPB.Board => BoardPageTabBarBuilderImpl(),
        ViewLayoutPB.Calendar => CalendarPageTabBarBuilderImpl(),
        ViewLayoutPB.Grid => MobileGridTabBarBuilderImpl(),
        _ => throw UnimplementedError,
      };

  FlowySvgData get iconData => layout.icon;

  bool get isSpace {
    try {
      if (extra.isEmpty) {
        return false;
      }

      final ext = jsonDecode(extra);
      final isSpace = ext[ViewExtKeys.isSpaceKey] ?? false;
      return isSpace;
    } catch (e) {
      return false;
    }
  }

  SpacePermission get spacePermission {
    try {
      final ext = jsonDecode(extra);
      final permission = ext[ViewExtKeys.spacePermissionKey] ?? 1;
      return SpacePermission.values[permission];
    } catch (e) {
      return SpacePermission.private;
    }
  }

  FlowySvg? buildSpaceIconSvg(BuildContext context, {Size? size}) {
    try {
      if (extra.isEmpty) {
        return null;
      }

      final ext = jsonDecode(extra);
      final icon = ext[ViewExtKeys.spaceIconKey];
      final color = ext[ViewExtKeys.spaceIconColorKey];
      if (icon == null || color == null) {
        return null;
      }
      // before version 0.6.7
      if (icon.contains('space_icon')) {
        return FlowySvg(
          FlowySvgData('assets/flowy_icons/16x/$icon.svg'),
          color: Theme.of(context).colorScheme.surface,
        );
      }

      final values = icon.split('/');
      if (values.length != 2) {
        return null;
      }
      final svgString = findLoadedIcon(values[0], values[1])?.content;
      if (svgString == null) {
        return null;
      }
      if (iconPackForGroup(values[0]).isColorful) {
        // multi-color artwork brings its own palette
        return FlowySvg.string(svgString, size: size, blendMode: null);
      }
      return FlowySvg.string(
        svgString,
        color: Theme.of(context).colorScheme.surface,
        size: size,
      );
    } catch (e) {
      return null;
    }
  }

  String? get spaceIcon {
    try {
      final ext = jsonDecode(extra);
      final icon = ext[ViewExtKeys.spaceIconKey];
      return icon;
    } catch (e) {
      return null;
    }
  }

  String? get spaceIconColor {
    try {
      final ext = jsonDecode(extra);
      final color = ext[ViewExtKeys.spaceIconColorKey];
      return color;
    } catch (e) {
      return null;
    }
  }

  bool get isPinned {
    try {
      final ext = jsonDecode(extra);
      final isPinned = ext[ViewExtKeys.isPinnedKey] ?? false;
      return isPinned;
    } catch (e) {
      return false;
    }
  }

  PageStyleCover? get cover {
    try {
      return ViewCoverCodec.decodeCover(extra);
    } on FormatException {
      return null;
    }
  }

  PageStyleLineHeightLayout get lineHeightLayout {
    if (layout != ViewLayoutPB.Document) {
      return PageStyleLineHeightLayout.normal;
    }
    try {
      final ext = jsonDecode(extra);
      final lineHeight = ext[ViewExtKeys.lineHeightLayoutKey];
      return PageStyleLineHeightLayout.fromString(lineHeight);
    } catch (e) {
      return PageStyleLineHeightLayout.normal;
    }
  }

  PageStyleFontLayout get fontLayout {
    if (layout != ViewLayoutPB.Document) {
      return PageStyleFontLayout.normal;
    }
    try {
      final ext = jsonDecode(extra);
      final fontLayout = ext[ViewExtKeys.fontLayoutKey];
      return PageStyleFontLayout.fromString(fontLayout);
    } catch (e) {
      return PageStyleFontLayout.normal;
    }
  }

  @visibleForTesting
  set isSpace(bool value) {
    try {
      if (extra.isEmpty) {
        extra = jsonEncode({ViewExtKeys.isSpaceKey: value});
      } else {
        final ext = jsonDecode(extra);
        ext[ViewExtKeys.isSpaceKey] = value;
        extra = jsonEncode(ext);
      }
    } catch (e) {
      extra = jsonEncode({ViewExtKeys.isSpaceKey: value});
    }
  }
}

extension ViewLayoutExtension on ViewLayoutPB {
  FlowySvgData get icon => switch (this) {
        ViewLayoutPB.Board => FlowySvgs.icon_board_s,
        ViewLayoutPB.Calendar => FlowySvgs.icon_calendar_s,
        ViewLayoutPB.Grid => FlowySvgs.icon_grid_s,
        ViewLayoutPB.Document => FlowySvgs.icon_document_s,
        ViewLayoutPB.Chat => FlowySvgs.chat_ai_page_s,
        _ => FlowySvgs.icon_document_s,
      };

  bool get isDocumentView => switch (this) {
        ViewLayoutPB.Document => true,
        ViewLayoutPB.Chat ||
        ViewLayoutPB.Grid ||
        ViewLayoutPB.Board ||
        ViewLayoutPB.Calendar =>
          false,
        _ => throw Exception('Unknown layout type'),
      };

  bool get isDatabaseView => switch (this) {
        ViewLayoutPB.Grid ||
        ViewLayoutPB.Board ||
        ViewLayoutPB.Calendar =>
          true,
        ViewLayoutPB.Document || ViewLayoutPB.Chat => false,
        _ => throw Exception('Unknown layout type'),
      };

  String get defaultName => switch (this) {
        ViewLayoutPB.Document => '',
        _ => LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
      };

  bool get shrinkWrappable => switch (this) {
        ViewLayoutPB.Grid => true,
        ViewLayoutPB.Board => true,
        _ => false,
      };

  double get pluginHeight => switch (this) {
        ViewLayoutPB.Document || ViewLayoutPB.Board || ViewLayoutPB.Chat => 450,
        ViewLayoutPB.Calendar => 650,
        ViewLayoutPB.Grid => double.infinity,
        _ => throw UnimplementedError(),
      };
}

extension ViewFinder on List<ViewPB> {
  ViewPB? findView(String id) {
    for (final view in this) {
      if (view.id == id) {
        return view;
      }

      if (view.childViews.isNotEmpty) {
        final v = view.childViews.findView(id);
        if (v != null) {
          return v;
        }
      }
    }

    return null;
  }
}
