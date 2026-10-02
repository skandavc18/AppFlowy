import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _event(
  String name, {
  String frame = 'main',
  String loader = 'a',
}) =>
    {'name': name, 'frameId': frame, 'loaderId': loader};

void main() {
  test('the main frame painting its document is the signal', () {
    final signal = WebEmbedPaintSignal()..setMainFrame('main');
    expect(signal.painted(_event('init')), isFalse);
    expect(signal.painted(_event('firstPaint')), isFalse);
    expect(signal.painted(_event('firstContentfulPaint')), isTrue);
  });

  test('a frame inside the page painting is not', () {
    final signal = WebEmbedPaintSignal()..setMainFrame('main');
    expect(signal.painted(_event('init', frame: 'ad')), isFalse);
    expect(
      signal.painted(_event('firstContentfulPaint', frame: 'ad')),
      isFalse,
    );
  });

  test('a paint missed before the main frame was known is replayed', () {
    final signal = WebEmbedPaintSignal();
    expect(signal.painted(_event('init')), isFalse);
    expect(
      signal.painted(_event('firstContentfulPaint', frame: 'ad')),
      isFalse,
    );
    expect(signal.painted(_event('firstContentfulPaint')), isFalse);
    expect(signal.setMainFrame('main'), isTrue);
  });

  test('a first load whose document was created unseen still counts', () {
    final signal = WebEmbedPaintSignal()..setMainFrame('main');
    expect(signal.painted(_event('firstContentfulPaint', loader: 'z')), isTrue);
  });

  test('once its document is known, only that document paints for it', () {
    final signal = WebEmbedPaintSignal()..setMainFrame('main');
    signal.painted(_event('init', loader: 'b'));
    expect(signal.painted(_event('firstContentfulPaint')), isFalse);
    expect(signal.painted(_event('firstContentfulPaint', loader: 'b')), isTrue);
  });

  test('a reload waits for its new document, never the one it replaces', () {
    final signal = WebEmbedPaintSignal()..setMainFrame('main');
    signal.painted(_event('init'));
    signal.restart();
    expect(signal.painted(_event('firstContentfulPaint')), isFalse);
    expect(signal.painted(_event('init', loader: 'b')), isFalse);
    expect(signal.painted(_event('firstContentfulPaint')), isFalse);
    expect(signal.painted(_event('firstContentfulPaint', loader: 'b')), isTrue);
  });

  test('a reload forgets what came before the main frame was known', () {
    final signal = WebEmbedPaintSignal()
      ..painted(_event('firstContentfulPaint'))
      ..restart();
    expect(signal.setMainFrame('main'), isFalse);
  });

  test('anything but an event is ignored', () {
    final signal = WebEmbedPaintSignal()..setMainFrame('main');
    expect(signal.painted(null), isFalse);
    expect(signal.painted('firstContentfulPaint'), isFalse);
  });
}
