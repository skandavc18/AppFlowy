import 'dart:async';
import 'dart:convert';

import 'package:appflowy/mobile/presentation/chat/mobile_chat_screen.dart';
import 'package:appflowy/mobile/presentation/database/board/mobile_board_screen.dart';
import 'package:appflowy/mobile/presentation/database/mobile_calendar_screen.dart';
import 'package:appflowy/mobile/presentation/database/mobile_grid_screen.dart';
import 'package:appflowy/mobile/presentation/plugin/mobile_plugin_screen.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Plugins that are workspace pages, which mobile opens through their view's
/// own route so the page gets its app bar, sharing and more menu.
const _pagePluginTypes = {
  PluginType.document,
  PluginType.grid,
  PluginType.board,
  PluginType.calendar,
  PluginType.chat,
};

({String id, DateTime at})? _lastMobileOpen;

/// Lets go of a plugin this never opened. Only its notifier exists before
/// [Plugin.init]; a page plugin's own dispose also closes the blocs init
/// creates, and throws on one that was never initialised — which used to stop
/// the page from opening at all.
void _release(Plugin plugin) => plugin.notifier?.dispose();

/// Opens [plugin] on mobile, where pages are routes rather than tabs.
///
/// Installed as [TabsBloc.mobileOpener], so every feature that opens a page
/// through the tabs on desktop opens it on mobile too.
Future<void> openPluginOnMobile(Plugin plugin, ViewPB? view) async {
  if (plugin.pluginType == PluginType.blank) return;
  final id = view?.id ?? plugin.id;
  final now = DateTime.now();
  final last = _lastMobileOpen;
  // Several desktop paths open the same page twice in quick succession.
  if (last != null &&
      last.id == id &&
      now.difference(last.at) < const Duration(milliseconds: 500)) {
    _release(plugin);
    return;
  }
  _lastMobileOpen = (id: id, at: now);

  final context = AppGlobals.rootNavKey.currentContext;
  if (context == null) {
    _release(plugin);
    return;
  }
  if (!_pagePluginTypes.contains(plugin.pluginType)) {
    await context.push(
      MobilePluginScreen.location(plugin.pluginType),
      extra: plugin,
    );
    return;
  }
  // The page's route builds its own plugin from the view.
  _release(plugin);
  final target = view ?? (await ViewBackendService.getView(id)).toNullable();
  if (target == null || !context.mounted) return;
  await context.pushView(target);
}

extension MobileRouter on BuildContext {
  Future<void> pushView(
    ViewPB view, {
    Map<String, dynamic>? arguments,
    bool addInRecent = true,
    bool showMoreButton = true,
    String? fixedTitle,
    String? blockId,
    List<String>? tabs,
  }) async {
    // set the current view before pushing the new view
    getIt<MenuSharedState>().latestOpenView = view;
    unawaited(getIt<CachedRecentService>().updateRecentViews([view.id], true));
    final queryParameters = view.queryParameters(arguments);

    if (view.layout == ViewLayoutPB.Document) {
      queryParameters[MobileDocumentScreen.viewShowMoreButton] =
          showMoreButton.toString();
      if (fixedTitle != null) {
        queryParameters[MobileDocumentScreen.viewFixedTitle] = fixedTitle;
      }
      if (blockId != null) {
        queryParameters[MobileDocumentScreen.viewBlockId] = blockId;
      }
    }
    if (tabs != null) {
      queryParameters[MobileDocumentScreen.viewSelectTabs] = tabs.join('-');
    }

    final uri = Uri(
      path: view.routeName,
      queryParameters: queryParameters,
    ).toString();
    await push(uri);
  }
}

extension on ViewPB {
  String get routeName {
    switch (layout) {
      case ViewLayoutPB.Document:
        return MobileDocumentScreen.routeName;
      case ViewLayoutPB.Grid:
        return MobileGridScreen.routeName;
      case ViewLayoutPB.Calendar:
        return MobileCalendarScreen.routeName;
      case ViewLayoutPB.Board:
        return MobileBoardScreen.routeName;
      case ViewLayoutPB.Chat:
        return MobileChatScreen.routeName;

      default:
        throw UnimplementedError('routeName for $this is not implemented');
    }
  }

  Map<String, dynamic> queryParameters([Map<String, dynamic>? arguments]) {
    switch (layout) {
      case ViewLayoutPB.Document:
        return {
          MobileDocumentScreen.viewId: id,
          MobileDocumentScreen.viewTitle: name,
        };
      case ViewLayoutPB.Grid:
        return {
          MobileGridScreen.viewId: id,
          MobileGridScreen.viewTitle: name,
          MobileGridScreen.viewArgs: jsonEncode(arguments),
        };
      case ViewLayoutPB.Calendar:
        return {
          MobileCalendarScreen.viewId: id,
          MobileCalendarScreen.viewTitle: name,
        };
      case ViewLayoutPB.Board:
        return {
          MobileBoardScreen.viewId: id,
          MobileBoardScreen.viewTitle: name,
        };
      case ViewLayoutPB.Chat:
        return {
          MobileChatScreen.viewId: id,
          MobileChatScreen.viewTitle: name,
        };
      default:
        throw UnimplementedError(
          'queryParameters for $this is not implemented',
        );
    }
  }
}
