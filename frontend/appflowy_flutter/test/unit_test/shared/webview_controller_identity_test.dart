import 'package:appflowy/shared/find_replace/webview_find.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sameWebViewController', () {
    test('matches distinct public wrappers for the same platform', () {
      final platform = _PlatformControllerFake(1);
      final first = InAppWebViewController.fromPlatform(platform: platform);
      final second = InAppWebViewController.fromPlatform(platform: platform);

      expect(identical(first, second), isFalse);
      expect(first == second, isFalse);
      expect(identical(first.platform, second.platform), isTrue);
      expect(sameWebViewController(first, second), isTrue);
      expect(sameWebViewController(second, first), isTrue);
      expect(sameWebViewController(first, first), isTrue);
    });

    test('rejects different platform objects with the same view ID', () {
      final first = InAppWebViewController.fromPlatform(
        platform: _PlatformControllerFake(1),
      );
      final second = InAppWebViewController.fromPlatform(
        platform: _PlatformControllerFake(1),
      );

      expect(identical(first.platform, second.platform), isFalse);
      expect(first.getViewId(), second.getViewId());
      expect(sameWebViewController(first, second), isFalse);
      expect(sameWebViewController(second, first), isFalse);
    });

    test('rejects null controllers including two nulls', () {
      final controller = InAppWebViewController.fromPlatform(
        platform: _PlatformControllerFake(1),
      );

      expect(sameWebViewController(null, null), isFalse);
      expect(sameWebViewController(controller, null), isFalse);
      expect(sameWebViewController(null, controller), isFalse);
    });

    test('captured controller becomes stale after rebinding', () {
      final platform = _PlatformControllerFake(1);
      final captured = InAppWebViewController.fromPlatform(platform: platform);
      InAppWebViewController? current =
          InAppWebViewController.fromPlatform(platform: platform);
      bool isCurrent() => sameWebViewController(captured, current);

      expect(isCurrent(), isTrue);
      current = InAppWebViewController.fromPlatform(
        platform: _PlatformControllerFake(1),
      );
      expect(isCurrent(), isFalse);
      current = null;
      expect(isCurrent(), isFalse);
    });
  });
}

class _PlatformControllerFake extends Fake
    implements PlatformInAppWebViewController {
  _PlatformControllerFake(this.id);

  @override
  final int id;

  @override
  int getViewId() => id;
}
