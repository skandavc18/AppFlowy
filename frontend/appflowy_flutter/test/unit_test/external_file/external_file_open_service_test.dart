import 'package:appflowy/plugins/external_file/external_file_plugin.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/external_file/external_file_open_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/external_file_open_host.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ExternalFileOpenService.instance;
  final first = p.absolute('notes', 'first.md');
  final second = p.absolute('notes', 'second file.txt');
  final third = p.absolute('notes', 'third.html');

  // Hands anything still waiting to a throwaway opener, so no test sees the
  // files another one left behind.
  void drain() {
    void discard(List<String> _) {}
    service
      ..attach(discard)
      ..detach(discard);
  }

  group('normalizeExternalFilePath', () {
    final posix = p.Context(style: p.Style.posix, current: '/home/me');
    final windows = p.Context(style: p.Style.windows, current: r'C:\Users\me');

    test('keeps an absolute path, trimmed and normalized', () {
      expect(
        normalizeExternalFilePath(' /home/me/./a/../notes.md\n', context: posix),
        '/home/me/notes.md',
      );
      expect(
        normalizeExternalFilePath(r'C:\Users\me\a\..\notes.md', context: windows),
        r'C:\Users\me\notes.md',
      );
    });

    test('resolves a relative path against the working directory', () {
      expect(
        normalizeExternalFilePath('docs/notes.md', context: posix),
        '/home/me/docs/notes.md',
      );
      expect(
        normalizeExternalFilePath(r'docs\notes.md', context: windows),
        r'C:\Users\me\docs\notes.md',
      );
    });

    test('decodes a file URI', () {
      expect(
        normalizeExternalFilePath(
          'file:///home/me/My%20Notes.md',
          context: posix,
        ),
        '/home/me/My Notes.md',
      );
      expect(
        normalizeExternalFilePath('FILE:///tmp/a.md', context: posix),
        '/tmp/a.md',
      );
      expect(
        normalizeExternalFilePath(
          'file:///C:/Users/me/My%20Notes.md',
          context: windows,
        ),
        r'C:\Users\me\My Notes.md',
      );
      expect(
        normalizeExternalFilePath(
          'file://server/share/a.md',
          context: windows,
        ),
        r'\\server\share\a.md',
      );
    });

    test('takes a drive letter for part of a path', () {
      expect(
        normalizeExternalFilePath('C://Users/me/a.md', context: windows),
        r'C:\Users\me\a.md',
      );
    });

    test('rejects whatever names no local file', () {
      for (final value in [
        '',
        '  ',
        'file://server/share/a.md',
        'appflowy-flutter://invitation-callback?workspace=1',
        'https://example.com/notes.md',
      ]) {
        expect(
          normalizeExternalFilePath(value, context: posix),
          isNull,
          reason: value,
        );
      }
      expect(
        normalizeExternalFilePath('sftp://host/notes.md', context: windows),
        isNull,
      );
    });
  });

  group('ExternalFileOpenService', () {
    setUp(drain);
    tearDown(drain);

    test('holds files until the home screen attaches, then passes them on',
        () {
      final opened = <List<String>>[];
      void opener(List<String> paths) => opened.add(paths);

      service
        ..receive([first, p.toUri(second).toString(), first, ''])
        ..receive([second, third]);
      expect(opened, isEmpty);

      service.attach(opener);
      expect(opened, [
        [first, second, third],
      ]);

      service.receive([third, first]);
      expect(opened.last, [third, first]);

      service
        ..detach(opener)
        ..receive([first]);
      expect(opened, hasLength(2));
    });

    test('ignores a batch with nothing to open', () {
      final opened = <List<String>>[];
      service
        ..attach(opened.add)
        ..receive(['', 'appflowy-flutter://open']);
      expect(opened, isEmpty);
    });

    test('lets only the attached opener detach itself', () {
      final opened = <String>[];
      void opener(List<String> paths) => opened.addAll(paths);
      void stale(List<String> _) {}

      service
        ..attach(opener)
        ..detach(stale)
        ..receive([first]);
      expect(opened, [first]);
    });

    test('does nothing when the runner cannot open files', () async {
      await expectLater(service.start(), completes);
    });

    test('reads the files that launched AppFlowy, then listens for more',
        () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel(ExternalFileOpenService.channelName);
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return [first, p.toUri(second).toString()];
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await service.start();
      expect(calls, ['takePendingFiles']);

      final opened = <List<String>>[];
      service.attach(opened.add);
      expect(opened, [
        [first, second],
      ]);

      Future<ByteData?> send(MethodCall call) async {
        ByteData? reply;
        await messenger.handlePlatformMessage(
          ExternalFileOpenService.channelName,
          const StandardMethodCodec().encodeMethodCall(call),
          (data) => reply = data,
        );
        return reply;
      }

      await send(MethodCall('openFiles', [third, 7]));
      expect(opened.last, [third]);

      expect(await send(const MethodCall('somethingElse')), isNull);
      expect(opened, hasLength(2));
    });
  });

  group('opening files in tabs', () {
    setUp(() {
      getIt.registerSingleton<PluginSandbox>(
        PluginSandbox()
          ..registerPlugin(
            PluginType.externalFile,
            ExternalFilePluginBuilder(),
            config: ExternalFilePluginConfig(),
          ),
      );
      getIt.registerSingleton<MenuSharedState>(MenuSharedState());
      drain();
    });

    tearDown(() async {
      drain();
      getIt<MenuSharedState>().notifier.dispose();
      await getIt.unregister<MenuSharedState>();
      await getIt.unregister<PluginSandbox>();
    });

    List<String?> openPaths(TabsBloc tabs) => [
          for (final manager in tabs.state.pageManagers)
            switch (manager.plugin) {
              final ExternalFilePlugin plugin => plugin.path,
              _ => null,
            },
        ];

    testWidgets('each file gets a tab, and an open file is shown again',
        (tester) async {
      final tabs = TabsBloc();
      addTearDown(tabs.close);

      // The file AppFlowy was launched with waits for the home screen and
      // takes the empty tab it starts with.
      service.receive([first]);
      await tester.pumpWidget(
        BlocProvider.value(
          value: tabs,
          child: const ExternalFileOpenHost(child: SizedBox()),
        ),
      );
      await tester.pump();
      expect(openPaths(tabs), [first]);

      service.receive([second]);
      await tester.pump();
      expect(openPaths(tabs), [first, second]);
      expect(tabs.state.currentIndex, 1);

      final firstPlugin =
          tabs.state.pageManagers.first.plugin as ExternalFilePlugin;
      service.receive([first]);
      await tester.pump();
      expect(openPaths(tabs), [first, second]);
      expect(tabs.state.currentIndex, 0);
      expect(tabs.state.pageManagers.first.plugin, same(firstPlugin));
      expect(firstPlugin.revision.value, 1);

      // Once the home screen is gone, files wait for the next one.
      await tester.pumpWidget(const SizedBox());
      service.receive([third]);
      await tester.pump();
      expect(openPaths(tabs), [first, second]);
    });

    test('a pinned empty tab is kept beside the file', () async {
      final tabs = TabsBloc();
      addTearDown(tabs.close);
      tabs.state.currentPageManager.isPinned = true;

      final changed = tabs.stream.first;
      tabs.add(
        TabsEvent.openStandaloneTab(plugin: ExternalFilePlugin(path: first)),
      );
      await changed;

      expect(openPaths(tabs), [null, first]);
      expect(tabs.state.currentIndex, 1);
    });
  });
}
