import 'dart:async';

import 'package:appflowy/shared/window_title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_platform/universal_platform.dart';

const _channel = MethodChannel('window_manager');
const _maximize = ValueKey('window-caption-maximize');
const _restore = ValueKey('window-caption-restore');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hasCaptions = UniversalPlatform.isLinux || UniversalPlatform.isWindows;
  final calls = <MethodCall>[];
  var maximized = false;
  var fullScreen = false;

  setUp(() {
    calls.clear();
    maximized = false;
    fullScreen = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isMaximized' => maximized,
        'isFullScreen' => fullScreen,
        // setFullScreen nudges the window's size on Windows.
        'getBounds' => {'x': 0.0, 'y': 0.0, 'width': 800.0, 'height': 600.0},
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> pumpTitleBar(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WindowTitleBar(backgroundColor: Colors.black)),
      ),
    );
    await tester.pump();
  }

  // An event as the native side sends it when the window's state changes.
  // Not awaited: the test zone runs its microtasks only when pumped.
  Future<void> windowEvent(WidgetTester tester, String name) async {
    unawaited(
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onEvent', {'eventName': name}),
        ),
        null,
      ),
    );
    await tester.pump();
  }

  List<String> requests() => [
        for (final call in calls)
          if (!call.method.startsWith('is') && call.method != 'getBounds')
            call.method,
      ];

  Future<void> expectLeavesFullScreen(WidgetTester tester) async {
    calls.clear();
    await tester.tap(find.byKey(_restore));
    await tester.pump();
    final call = calls.singleWhere((c) => c.method == 'setFullScreen');
    expect(call.arguments, {'isFullScreen': false});
    expect(requests(), isNot(contains('maximize')));
    expect(requests(), isNot(contains('unmaximize')));
  }

  testWidgets(
    'maximize button maximizes a normal window',
    (tester) async {
      await pumpTitleBar(tester);
      expect(find.byKey(_restore), findsNothing);
      await tester.tap(find.byKey(_maximize));
      await tester.pump();
      expect(requests(), ['maximize']);
    },
    skip: !hasCaptions,
  );

  testWidgets(
    'a maximize the desktop turns into full screen can be restored',
    (tester) async {
      await pumpTitleBar(tester);
      await tester.tap(find.byKey(_maximize));
      await tester.pump();
      // What mac-ui's Spaces on GNOME reports for the maximize button: the
      // window goes full screen instead and its maximize is dropped.
      await windowEvent(tester, 'maximize');
      await windowEvent(tester, 'unmaximize');
      await windowEvent(tester, 'enter-full-screen');
      expect(find.byKey(_maximize), findsNothing);

      await expectLeavesFullScreen(tester);
      await windowEvent(tester, 'leave-full-screen');
      expect(find.byKey(_maximize), findsOneWidget);
      expect(find.byKey(_restore), findsNothing);
    },
    skip: !hasCaptions,
  );

  testWidgets(
    'a title bar made while the window is full screen offers to restore it',
    (tester) async {
      fullScreen = true;
      await pumpTitleBar(tester);
      expect(find.byKey(_maximize), findsNothing);
      await expectLeavesFullScreen(tester);
    },
    skip: !hasCaptions,
  );

  testWidgets(
    'a maximized window is unmaximized, and the button follows',
    (tester) async {
      maximized = true;
      await pumpTitleBar(tester);
      calls.clear();
      await tester.tap(find.byKey(_restore));
      await tester.pump();
      expect(requests(), ['unmaximize']);
      await windowEvent(tester, 'unmaximize');
      expect(find.byKey(_maximize), findsOneWidget);
    },
    skip: !hasCaptions,
  );
}
