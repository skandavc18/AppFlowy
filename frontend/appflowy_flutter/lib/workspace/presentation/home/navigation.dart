import 'dart:io';

import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:styled_widget/styled_widget.dart';

class NavigationNotifier with ChangeNotifier {
  NavigationNotifier({required this.navigationItems});

  List<NavigationItem> navigationItems;

  void update(PageNotifier notifier) {
    if (navigationItems != notifier.plugin.widgetBuilder.navigationItems) {
      navigationItems = notifier.plugin.widgetBuilder.navigationItems;
      notifyListeners();
    }
  }
}

class FlowyNavigation extends StatelessWidget {
  const FlowyNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProxyProvider<PageNotifier, NavigationNotifier>(
      create: (_) {
        final notifier = Provider.of<PageNotifier>(context, listen: false);
        return NavigationNotifier(
          navigationItems: notifier.plugin.widgetBuilder.navigationItems,
        );
      },
      update: (_, notifier, controller) => controller!..update(notifier),
      child: Expanded(
        child: Row(
          children: [
            Selector<NavigationNotifier, List<NavigationItem>>(
              selector: (context, notifier) => notifier.navigationItems,
              builder: (ctx, items, child) => Expanded(
                child: Row(
                  children: _renderNavigationItems(items),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _renderNavigationItems(List<NavigationItem> items) {
    if (items.isEmpty) {
      return [];
    }

    // A plugin may return the same (or an unmodifiable) list on every build.
    // Removing its last item used to erase the caption on the next navigation.
    final List<NavigationItem> newItems = List.of(_filter(items));
    final Widget last = NaviItemWidget(newItems.removeLast());

    final List<Widget> widgets = List.empty(growable: true);
    // widgets.addAll(newItems.map((item) => NaviItemDivider(child: NaviItemWidget(item))).toList());

    for (final item in newItems) {
      widgets.add(NaviItemWidget(item));
      widgets.add(const Text('/'));
    }

    widgets.add(last);

    return widgets;
  }

  List<NavigationItem> _filter(List<NavigationItem> items) {
    final length = items.length;
    if (length > 4) {
      final first = items[0];
      final ellipsisItems = items.getRange(1, length - 2).toList();
      final last = items.getRange(length - 2, length).toList();
      return [
        first,
        EllipsisNaviItem(items: ellipsisItems),
        ...last,
      ];
    } else {
      return items;
    }
  }
}

class NaviItemWidget extends StatelessWidget {
  const NaviItemWidget(this.item, {super.key});

  final NavigationItem item;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ViewTitleBarScope(
        child: item.leftBarItem.padding(vertical: 2),
      ),
    );
  }
}

class EllipsisNaviItem extends NavigationItem {
  EllipsisNaviItem({required this.items});

  final List<NavigationItem> items;

  @override
  String? get viewName => null;

  @override
  Widget get leftBarItem => FlowyText.medium('...', fontSize: FontSizes.s16);

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;

  @override
  NavigationCallback get action => (id) {};
}

TextSpan sidebarTooltipTextSpan(BuildContext context, String hintText) =>
    TextSpan(
      children: [
        TextSpan(
          text: "$hintText\n",
        ),
        TextSpan(
          text: Platform.isMacOS ? "⌘+." : "Ctrl+\\",
        ),
      ],
    );
