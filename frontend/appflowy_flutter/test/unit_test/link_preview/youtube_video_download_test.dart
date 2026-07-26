import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_embed_player.dart';
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

    test('accepts Shorts links, with or without share parameters', () {
      expect(
        isYoutubeVideoUrl('https://www.youtube.com/shorts/yIVRs6YSbOM'),
        isTrue,
      );
      expect(
        youtubeVideoId('https://youtube.com/shorts/yIVRs6YSbOM?si=abc123'),
        'yIVRs6YSbOM',
      );
    });
  });

  group('isYoutubeShortsUrl', () {
    test('only matches the Shorts path on YouTube hosts', () {
      expect(
        isYoutubeShortsUrl('https://www.youtube.com/shorts/yIVRs6YSbOM'),
        isTrue,
      );
      expect(
        isYoutubeShortsUrl('https://m.youtube.com/shorts/yIVRs6YSbOM?si=abc'),
        isTrue,
      );
      expect(
        isYoutubeShortsUrl('https://www.youtube.com/watch?v=yIVRs6YSbOM'),
        isFalse,
      );
      expect(
        isYoutubeShortsUrl('https://example.com/shorts/yIVRs6YSbOM'),
        isFalse,
      );
    });
  });

  group('initialYoutubeAspectRatio', () {
    test('starts Shorts in portrait and everything else widescreen', () {
      expect(
        initialYoutubeAspectRatio(
          'https://www.youtube.com/shorts/yIVRs6YSbOM',
        ),
        portraitVideoAspectRatio,
      );
      expect(
        initialYoutubeAspectRatio('https://youtu.be/yIVRs6YSbOM'),
        defaultVideoAspectRatio,
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

  group('YoutubeOfflineDownloadState', () {
    test('reports indeterminate progress when the size is unknown', () {
      expect(const YoutubeOfflineDownloadState().progress, isNull);
      expect(
        const YoutubeOfflineDownloadState(receivedBytes: 10, totalBytes: 0)
            .progress,
        isNull,
      );
    });

    test('reports a clamped ratio when the size is known', () {
      expect(
        const YoutubeOfflineDownloadState(receivedBytes: 25, totalBytes: 100)
            .progress,
        0.25,
      );
      expect(
        const YoutubeOfflineDownloadState(receivedBytes: 150, totalBytes: 100)
            .progress,
        1.0,
      );
    });
  });

  group('YoutubeOfflineDownloadManager', () {
    test('starts downloading without waiting for it to finish', () async {
      final completer = Completer<InternalYoutubeVideo>();
      final manager = YoutubeOfflineDownloadManager(
        downloader: (url, {onProgress}) {
          onProgress?.call(512, 1024);
          return completer.future;
        },
      );

      InternalYoutubeVideo? completed;
      manager.start(
        key: 'node',
        url: 'https://youtu.be/yIVRs6YSbOM',
        onCompleted: (video) async => completed = video,
      );

      // The call returns immediately, with progress already observable.
      expect(completed, isNull);
      expect(manager.progressOf('node')?.value.progress, 0.5);

      completer.complete((path: 'video.mp4', name: 'video.mp4'));
      await Future<void>.delayed(Duration.zero);

      expect(completed?.path, 'video.mp4');
      expect(manager.progressOf('node'), isNull);
    });

    test('ignores a second download for the same block', () {
      var started = 0;
      final manager = YoutubeOfflineDownloadManager(
        downloader: (url, {onProgress}) {
          started++;
          return Completer<InternalYoutubeVideo>().future;
        },
      );

      for (var i = 0; i < 2; i++) {
        manager.start(
          key: 'node',
          url: 'https://youtu.be/yIVRs6YSbOM',
          onCompleted: (_) async {},
        );
      }

      expect(started, 1);
    });

    test('reports a failure and forgets the download', () async {
      final manager = YoutubeOfflineDownloadManager(
        downloader: (url, {onProgress}) =>
            Future.error(Exception('no network')),
      );

      var failed = false;
      manager.start(
        key: 'node',
        url: 'https://youtu.be/yIVRs6YSbOM',
        onCompleted: (_) async {},
        onFailed: () => failed = true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(failed, isTrue);
      expect(manager.progressOf('node'), isNull);
    });
  });
}
