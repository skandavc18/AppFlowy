import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_video_download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isYoutubeVideoUrl', () {
    test('accepts supported YouTube video URL formats', () {
      expect(
        isYoutubeVideoUrl('https://www.youtube.com/watch?v=yIVRs6YSbOM'),
        isTrue,
      );
      expect(isYoutubeVideoUrl('https://youtu.be/yIVRs6YSbOM'), isTrue);
      expect(
        isYoutubeVideoUrl('https://www.youtube.com/embed/yIVRs6YSbOM'),
        isTrue,
      );
      expect(
        isYoutubeVideoUrl('https://m.youtube.com/watch?v=yIVRs6YSbOM'),
        isTrue,
      );
    });

    test('rejects non-video and lookalike URLs', () {
      expect(isYoutubeVideoUrl('https://www.youtube.com/'), isFalse);
      expect(
        isYoutubeVideoUrl(
          'https://example.com/watch?v=yIVRs6YSbOM',
        ),
        isFalse,
      );
      expect(
        isYoutubeVideoUrl(
          'https://youtube.com.example.com/watch?v=yIVRs6YSbOM',
        ),
        isFalse,
      );
    });
  });

  group('youtubeDownloadFileName', () {
    test('removes characters that are invalid in file names', () {
      expect(
        youtubeDownloadFileName('A: video? <demo> / test.', 'yIVRs6YSbOM'),
        'A_ video_ _demo_ _ test',
      );
    });

    test('falls back to the video ID for an empty title', () {
      expect(
        youtubeDownloadFileName('  ... ', 'yIVRs6YSbOM'),
        'yIVRs6YSbOM',
      );
    });
  });
}
