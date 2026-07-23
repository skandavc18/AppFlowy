import 'package:flutter/gestures.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters only pointer-scroll axes disabled by WebView settings', () {
    const delta = Offset(12, 40);

    expect(
      filterScrollDeltaForSettings(delta, {
        'initialSettings': {
          'disableHorizontalScroll': false,
          'disableVerticalScroll': true,
        },
      }),
      const Offset(12, 0),
    );
    expect(
      filterScrollDeltaForSettings(delta, {
        'initialSettings': {
          'disableHorizontalScroll': true,
          'disableVerticalScroll': true,
        },
      }),
      Offset.zero,
    );
    expect(filterScrollDeltaForSettings(delta, null), delta);
  });
}
