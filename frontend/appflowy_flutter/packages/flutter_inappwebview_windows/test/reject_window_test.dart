import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/in_app_webview_controller.dart'
    show InternalInAppWebViewController;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('public rejectWindow uses the opener channel and preserves full id',
      () async {
    final controller = WindowsInAppWebViewController(
      const WindowsInAppWebViewControllerCreationParams(id: 91),
    );
    const channel =
        MethodChannel('com.pichillilorenzo/flutter_inappwebview_91');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return calls.length == 1;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      controller.dispose();
    });
    const id = 0x100000001;
    expect(await controller.rejectWindow(id), isTrue);
    expect(await controller.rejectWindow(id), isFalse);
    expect(calls.map((call) => call.method), ['rejectWindow', 'rejectWindow']);
    expect(calls.map((call) => call.arguments), [
      {'windowId': id},
      {'windowId': id}
    ]);
    await expectLater(controller.rejectWindow(-1), throwsArgumentError);
    expect(calls, hasLength(2));
  });

  test('callback can await rejection then return true without loadUrl',
      () async {
    final calls = <String>[];
    final controller = WindowsInAppWebViewController(
      WindowsInAppWebViewControllerCreationParams(
        id: 92,
        webviewParams: PlatformInAppWebViewWidgetCreationParams(
          onCreateWindow: (controller, action) async {
            await (controller as WindowsInAppWebViewController)
                .rejectWindow(action.windowId);
            calls.add('return true');
            return true;
          },
        ),
      ),
    );
    const channel =
        MethodChannel('com.pichillilorenzo/flutter_inappwebview_92');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      controller.dispose();
    });
    final reply =
        await controller.handleMethod(const MethodCall('onCreateWindow', {
      'windowId': 7,
      'request': {'url': 'https://popup.invalid/'},
      'isForMainFrame': true,
      'hasGesture': false,
    }));
    expect(reply, isTrue);
    expect(calls, ['rejectWindow', 'return true']);
  });
}
