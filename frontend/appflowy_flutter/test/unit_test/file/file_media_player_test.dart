import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('recognizes video files from names and URLs', () {
    expect(fileMediaKind('Demo.MP4', null), FileMediaKind.video);
    expect(
      fileMediaKind(null, 'https://example.com/demo.webm?token=123'),
      FileMediaKind.video,
    );
  });

  test('recognizes audio files from names and URLs', () {
    expect(fileMediaKind('recording.mp3', null), FileMediaKind.audio);
    expect(
      fileMediaKind(null, 'https://example.com/music.flac?token=123'),
      FileMediaKind.audio,
    );
  });

  test('ignores unsupported file types', () {
    expect(fileMediaKind('document.pdf', null), isNull);
  });

  group('videoAspectRatioOf', () {
    test('prefers the display size over the raw frame size', () {
      expect(
        videoAspectRatioOf(
          const VideoParams(w: 1920, h: 1080, dw: 1080, dh: 1920),
        ),
        portraitVideoAspectRatio,
      );
    });

    test('falls back to the frame size', () {
      expect(
        videoAspectRatioOf(const VideoParams(w: 1920, h: 1080)),
        defaultVideoAspectRatio,
      );
    });

    test('is unknown until the video has been probed', () {
      expect(videoAspectRatioOf(const VideoParams()), isNull);
      expect(videoAspectRatioOf(const VideoParams(w: 0, h: 0)), isNull);
    });
  });
}
