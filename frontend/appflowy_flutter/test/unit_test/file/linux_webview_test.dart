import 'dart:async';

import 'package:appflowy_linux_webview/appflowy_linux_webview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('appflowy_linux_webview');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'create' ? 7 : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Map<Object?, Object?> argumentsOf(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;
  List<Map<Object?, Object?>> sent(String method) => [
        for (final call in calls)
          if (call.method == method) argumentsOf(call),
      ];
  List<Map<Object?, Object?>> pointer(String kind) => [
        for (final event in sent('pointer'))
          if (event['kind'] == kind) event,
      ];

  test('maps CSS cursors to Flutter cursors', () {
    expect(mouseCursorForCss('text'), SystemMouseCursors.text);
    expect(mouseCursorForCss('pointer'), SystemMouseCursors.click);
    expect(mouseCursorForCss('col-resize'), SystemMouseCursors.resizeColumn);
    expect(
      mouseCursorForCss(' NWSE-RESIZE '),
      SystemMouseCursors.resizeUpLeftDownRight,
    );
    expect(mouseCursorForCss('default'), SystemMouseCursors.basic);
    expect(mouseCursorForCss('unknown'), SystemMouseCursors.basic);
  });

  testWidgets('forwards input, geometry and cursor changes', (tester) async {
    final controller = await LinuxWebViewController.create(
      url: Uri.parse('http://127.0.0.1:4321/__appflowy__/office/t/'),
      userScripts: const ['script'],
    );
    expect(controller.textureId, 7);
    expect(calls.first.method, 'disposeAll');
    final create = sent('create').single;
    expect(create['origin'], 'http://127.0.0.1:4321');
    expect(create['userScripts'], ['script']);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300.5,
            height: 200,
            child: LinuxWebView(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(sent('active').single['active'], isTrue);
    final geometry = sent('geometry').last;
    // Whole pixels, so the texture is never stretched.
    expect(geometry['width'], 300);
    expect(geometry['height'], 200);
    expect(geometry['x'], (800 - 300.5) / 2);
    expect(geometry['y'], 200);

    final origin = tester.getTopLeft(find.byType(LinuxWebView));
    final click = await tester.startGesture(
      origin + const Offset(10, 20),
      kind: PointerDeviceKind.mouse,
    );
    await click.up();
    await tester.pump();
    final focusIndex = calls.indexWhere((call) => call.method == 'focus');
    final downIndex = calls.indexWhere(
      (call) => call.method == 'pointer' && argumentsOf(call)['kind'] == 'down',
    );
    expect(argumentsOf(calls[focusIndex])['focused'], isTrue);
    expect(focusIndex, lessThan(downIndex));
    // GDK reports the state from before a button's own press or release.
    expect(
      pointer('down').single,
      allOf(containsPair('button', 1), containsPair('buttons', 0)),
    );
    expect(
      pointer('up').single,
      allOf(containsPair('button', 1), containsPair('buttons', 1 << 8)),
    );
    expect(pointer('down').single['x'], 10);
    expect(pointer('down').single['y'], 20);

    final rightClick = await tester.startGesture(
      origin + const Offset(30, 40),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await rightClick.up();
    expect(pointer('down').last['button'], 3);
    expect(pointer('up').last['buttons'], 1 << 10);

    // Flutter scales a GDK scroll step to 53 logical pixels.
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: origin + const Offset(50, 50),
        scrollDelta: const Offset(0, 106),
      ),
    );
    expect(pointer('scroll').last['dy'], 2.0);
    // Without a host, wheels stay a mouse's, which WebKit scales like GTK.
    expect(pointer('scroll').last['precise'], isFalse);
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(position: origin + const Offset(50, 50)),
    );
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        position: origin + const Offset(50, 50),
        pan: const Offset(0, -53),
        panDelta: const Offset(0, -53),
      ),
    );
    expect(pointer('scroll').last['dy'], 1.0);

    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('cursor', {'id': create['id'], 'cursor': 'text'}),
      ),
      (_) {},
    );
    expect(controller.cursor.value, SystemMouseCursors.text);

    await tester.pumpWidget(
      TickerMode(
        enabled: false,
        child: LinuxWebView(controller: controller),
      ),
    );
    expect(sent('active').last['active'], isFalse);

    await controller.dispose();
    expect(sent('dispose').single['id'], create['id']);
    expect(controller.isDisposed, isTrue);
  });

  testWidgets('routes wheel and trackpad input through a scroll scope',
      (tester) async {
    final controller = await LinuxWebViewController.create(
      url: Uri.parse('http://127.0.0.1:4321/__appflowy__/office/t/'),
    );
    final wheels = <Offset>[];
    var consume = false;
    var starts = 0;
    final pans = <Offset>[];
    final releases = <Offset>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LinuxWebViewScrollScope(
          transform: (event) {
            wheels.add(event.scrollDelta);
            return consume
                ? Offset.zero
                : event.scrollDelta - const Offset(0, 13);
          },
          pixelWheel: true,
          trackpad: LinuxWebViewTrackpad(
            onStart: () => starts++,
            onUpdate: (delta) {
              pans.add(delta);
              return delta / 2;
            },
            onEnd: releases.add,
          ),
          child: LinuxWebView(controller: controller),
        ),
      ),
    );
    await tester.pump();
    final center = tester.getCenter(find.byType(LinuxWebView));

    // The host takes its part; the page gets the rest in exact pixels, 40 per
    // step of a precise (non-mouse) scroll in WebKit.
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 53)),
    );
    expect(wheels, [const Offset(0, 53)]);
    expect(pointer('scroll').single['dy'], 1.0);
    expect(pointer('scroll').single['precise'], isTrue);
    consume = true;
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 53)),
    );
    expect(pointer('scroll'), hasLength(1));

    Future<void> pan(int milliseconds, double total, double delta) =>
        tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: center,
            timeStamp: Duration(milliseconds: milliseconds),
            pan: Offset(0, total),
            panDelta: Offset(0, delta),
          ),
        );

    // Fingers moving up scroll down: the host sees scroll-delta sign.
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(position: center),
    );
    expect(starts, 1);
    for (var i = 1; i <= 4; i++) {
      await pan(10 * i, -20.0 * i, -20);
    }
    expect(pans, List.filled(4, const Offset(0, 20)));
    expect(pointer('scroll').last['dy'], 10 / 40);
    await tester.sendEventToBinding(
      PointerPanZoomEndEvent(
        position: center,
        timeStamp: const Duration(milliseconds: 45),
      ),
    );
    expect(releases.single.dx, 0);
    expect(releases.single.dy, closeTo(2000, 1e-6));

    // Fingers that rest before lifting stop rather than fling.
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(
        position: center,
        timeStamp: const Duration(milliseconds: 500),
      ),
    );
    await pan(510, -20, -20);
    await tester.sendEventToBinding(
      PointerPanZoomEndEvent(
        position: center,
        timeStamp: const Duration(milliseconds: 700),
      ),
    );
    expect(releases.last, Offset.zero);
    expect(starts, 2);

    // A gesture the view loses mid-way still ends for the host.
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(
        position: center,
        timeStamp: const Duration(seconds: 1),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(releases, hasLength(3));
    expect(releases.last, Offset.zero);
    await controller.dispose();
  });

  testWidgets('relays page messages and runs scripts', (tester) async {
    final controller = await LinuxWebViewController.create(
      url: Uri.parse('http://127.0.0.1:4321/__appflowy__/office/t/'),
    );
    final id = sent('create').single['id'];
    final received = <String>[];
    final subscription = controller.messages.listen(received.add);

    Future<void> post(Object? id, Object? message) =>
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('message', {'id': id, 'message': message}),
          ),
          (_) {},
        );
    await post(id, '{"t":"state"}');
    await post('view-unknown', 'stray');
    await post(id, 42);
    await tester.pump();
    expect(received, ['{"t":"state"}']);

    await controller.evaluateJavascript('window.go && window.go();');
    expect(
      sent('evaluate').single,
      allOf(
        containsPair('id', id),
        containsPair('source', 'window.go && window.go();'),
      ),
    );

    await controller.dispose();
    await post(id, 'late');
    await tester.pump();
    expect(received, hasLength(1));
    // The stream already finished; its cancel future is not fake-async's.
    unawaited(subscription.cancel());
  });
}
