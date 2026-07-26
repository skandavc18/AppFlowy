import 'package:appflowy/plugins/document/presentation/editor_plugins/media/video_player_controls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatVideoDuration', () {
    test('drops the hour when the video is shorter than one', () {
      expect(formatVideoDuration(const Duration(seconds: 9)), '0:09');
      expect(
        formatVideoDuration(const Duration(minutes: 12, seconds: 5)),
        '12:05',
      );
    });

    test('pads the minutes once the hour is shown', () {
      expect(
        formatVideoDuration(
          const Duration(hours: 1, minutes: 2, seconds: 9),
        ),
        '1:02:09',
      );
    });

    test('never shows a negative position', () {
      expect(formatVideoDuration(const Duration(seconds: -5)), '0:00');
    });
  });

  group('formatPlaybackSpeed', () {
    test('trims trailing zeros', () {
      expect(formatPlaybackSpeed(2), '2×');
      expect(formatPlaybackSpeed(1.5), '1.5×');
      expect(formatPlaybackSpeed(0.25), '0.25×');
    });
  });

  test('seeks in five second steps', () {
    expect(videoSeekStep, const Duration(seconds: 5));
  });
}
