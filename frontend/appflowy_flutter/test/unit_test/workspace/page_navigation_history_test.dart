import 'dart:async';

import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/page_navigation_history.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PageHistoryEntry entry(String id) =>
      PageHistoryEntry(pluginType: PluginType.document, viewId: id);

  test('history follows visits, deduplicates and drops the forward branch', () {
    final history = PageNavigationHistory();
    expect(history.canGoBack, isFalse);
    expect(history.canGoForward, isFalse);
    for (final id in ['a', 'b', 'c', 'c']) {
      history.record(entry(id));
    }
    expect(history.peek(forward: false)?.viewId, 'b');
    history.move(forward: false);
    history.record(entry('b'));
    expect(history.canGoForward, isTrue);
    history.move(forward: false);
    expect(history.current?.viewId, 'a');
    expect(history.canGoBack, isFalse);
    history.move(forward: true);
    expect(history.current?.viewId, 'b');
    history.record(entry('d'));
    expect(history.canGoForward, isFalse);
    expect(history.peek(forward: false)?.viewId, 'b');
  });

  test('missing entries, capacity and workspace reset are bounded', () {
    final history = PageNavigationHistory(capacity: 3);
    for (final id in ['a', 'b', 'c', 'd']) {
      history.record(entry(id));
    }
    history.discard(history.peek(forward: false)!);
    expect(history.current?.viewId, 'd');
    history.move(forward: false);
    expect(history.current?.viewId, 'b');
    expect(history.canGoBack, isFalse);
    history.clear();
    expect(history.current, isNull);
    expect(history.canGoForward, isFalse);
  });

  group('TabsBloc visit navigation', () {
    late MenuSharedState menu;
    late TabsBloc tabs;
    final loaded = <String>[];
    Future<ViewPB?> Function(String)? loader;

    setUp(() {
      menu = MenuSharedState();
      getIt.registerSingleton<MenuSharedState>(menu);
      getIt.registerSingleton<PluginSandbox>(PluginSandbox());
      loaded.clear();
      loader = null;
      tabs = TabsBloc(
        loadHistoryView: (id) async {
          loaded.add(id);
          return loader != null ? await loader!(id) : _view(id);
        },
        buildHistoryPlugin: (view) => _Plugin(view.id),
      );
    });

    tearDown(() async {
      await tabs.close();
      menu.notifier.dispose();
      await getIt.unregister<MenuSharedState>();
      await getIt.unregister<PluginSandbox>();
    });

    Future<void> open(String id) async {
      final next = tabs.stream.first;
      tabs.add(
        TabsEvent.openPlugin(
          plugin: _Plugin(id),
          view: _view(id),
          setLatest: false,
        ),
      );
      await next;
    }

    Future<void> back() async {
      final next = tabs.stream.first;
      tabs.goBack();
      await next;
    }

    Future<void> forward() async {
      final next = tabs.stream.first;
      tabs.goForward();
      await next;
    }

    test('recreates disposed pages and walks both directions once', () async {
      await open('a');
      final first = tabs.state.currentPageManager.plugin as _Plugin;
      await open('b');
      expect(first.disposed, isTrue);
      await open('c');
      expect(tabs.canGoBack, isTrue);
      await back();
      expect(tabs.state.currentPageManager.plugin.id, 'b');
      expect(tabs.canGoForward, isTrue);
      await back();
      expect(tabs.state.currentPageManager.plugin.id, 'a');
      expect(tabs.state.currentPageManager.plugin, isNot(same(first)));
      expect(tabs.canGoBack, isFalse);
      await forward();
      expect(tabs.state.currentPageManager.plugin.id, 'b');
      await open('d');
      expect(tabs.canGoForward, isFalse);
      expect(loaded, ['b', 'a', 'b']);
    });

    test('tab order and repeated selection are not visit history', () async {
      await open('a');
      var next = tabs.stream.first;
      tabs.add(TabsEvent.openTab(plugin: _Plugin('b'), view: _view('b')));
      await next;
      final b = tabs.state.currentPageManager;
      next = tabs.stream.first;
      tabs.add(const TabsEvent.selectTab(0));
      await next;
      next = tabs.stream.first;
      tabs.reorderTab(0, 2);
      await next;
      await back();
      expect(tabs.state.currentPageManager, same(b));
      expect(loaded, isEmpty);
      await forward();
      expect(tabs.state.currentPageManager.plugin.id, 'a');
    });

    test('deleted or unavailable pages are skipped', () async {
      await open('a');
      await open('b');
      await open('c');
      loader = (id) async => id == 'b' ? null : _view(id);
      await back();
      expect(loaded, ['b', 'a']);
      expect(tabs.state.currentPageManager.plugin.id, 'a');
      await forward();
      expect(tabs.state.currentPageManager.plugin.id, 'c');
    });

    test('a slow replay cannot overwrite newer page navigation', () async {
      await open('a');
      await open('b');
      final requested = Completer<void>();
      final pending = Completer<ViewPB?>();
      loader = (_) {
        requested.complete();
        return pending.future;
      };
      tabs.goBack();
      await requested.future;
      tabs.goBack(); // one pending traversal only
      await open('c');
      pending.complete(_view('a'));
      await Future<void>.delayed(Duration.zero);
      expect(tabs.state.currentPageManager.plugin.id, 'c');
      expect(loaded, ['a']);
      expect(tabs.navigationHistory.current?.viewId, 'c');
    });

    test('workspace changes clear history and invalidate pending replay',
        () async {
      await open('a');
      await open('b');
      final requested = Completer<void>();
      final pending = Completer<ViewPB?>();
      loader = (_) {
        requested.complete();
        return pending.future;
      };
      tabs.goBack();
      await requested.future;
      tabs.add(const TabsEvent.switchWorkspace('another-workspace'));
      await Future<void>.delayed(Duration.zero);
      pending.complete(_view('a'));
      await Future<void>.delayed(Duration.zero);
      expect(tabs.navigationHistory.current, isNull);
      expect(tabs.canGoBack, isFalse);
      expect(tabs.canGoForward, isFalse);
    });

    test('stale lookup cannot block history after a new visit', () async {
      await open('a');
      await open('b');
      final requested = Completer<void>();
      final pending = Completer<ViewPB?>();
      loader = (_) {
        requested.complete();
        return pending.future;
      };
      try {
        tabs.goBack();
        await requested.future;
        final next = tabs.stream.first;
        tabs.add(TabsEvent.openTab(plugin: _Plugin('c'), view: _view('c')));
        await next;
        expect(tabs.canGoBack, isTrue);
        await back();
        expect(tabs.state.currentPageManager.plugin.id, 'b');
        expect(loaded, ['a']);
      } finally {
        pending.complete(_view('a'));
        await Future<void>.delayed(Duration.zero);
      }
      expect(tabs.state.currentPageManager.plugin.id, 'b');
      expect(tabs.canGoForward, isTrue);
    });
  });
}

ViewPB _view(String id) =>
    ViewPB(id: id, parentViewId: 'workspace', layout: ViewLayoutPB.Document);

class _Plugin extends Plugin {
  _Plugin(this.id) : notifier = _Notifier(_view(id));
  @override
  final String id;
  bool disposed = false;
  @override
  final ViewPluginNotifier notifier;
  @override
  PluginType get pluginType => PluginType.document;
  @override
  PluginWidgetBuilder get widgetBuilder => throw UnimplementedError();
  @override
  void dispose() {
    disposed = true;
    notifier.dispose();
  }
}

class _Notifier implements ViewPluginNotifier {
  _Notifier(this.view);
  @override
  ViewPB view;
  @override
  final isDeleted = ValueNotifier<DeletedViewPB?>(null);
  @override
  void dispose() => isDeleted.dispose();
}
