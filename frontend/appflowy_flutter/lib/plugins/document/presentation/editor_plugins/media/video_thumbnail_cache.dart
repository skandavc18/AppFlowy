import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy_backend/log.dart';
import 'package:crypto/crypto.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Poster frames for local video files.
///
/// media_kit can hand back the frame mpv currently holds, so a clip shows a
/// real still rather than a placeholder. Grabbing one costs a short lived
/// player, so every frame is written to disk and every clip is only decoded
/// once per version of the file.
class VideoThumbnailCache {
  VideoThumbnailCache._();

  static final VideoThumbnailCache instance = VideoThumbnailCache._();

  static const _decodeTimeout = Duration(seconds: 12);

  final Map<String, Future<File?>> _inFlight = {};

  /// The poster for [videoPath], or null when no frame could be decoded.
  Future<File?> thumbnailFor(String videoPath) async {
    final source = File(videoPath);
    final FileStat stat;
    try {
      stat = await source.stat();
    } on FileSystemException {
      return null;
    }
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }

    // Keyed by the file's identity, so replacing a clip invalidates its
    // poster while a failed decode is not retried on every rebuild.
    final key = sha1
        .convert(
          utf8.encode(
            '$videoPath|${stat.modified.millisecondsSinceEpoch}|${stat.size}',
          ),
        )
        .toString();
    return _inFlight.putIfAbsent(key, () => _resolve(videoPath, key));
  }

  /// Starts decoding the poster without waiting for it.
  ///
  /// Called the moment a clip lands in the workspace so the sidebar has a
  /// still ready by the time anyone looks at it.
  void warmUp(String videoPath) {
    if (!videoExtensionRegex.hasMatch(videoPath.toLowerCase())) {
      return;
    }
    unawaited(thumbnailFor(videoPath));
  }

  Future<File?> _resolve(String videoPath, String key) async {
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'appflowy_video_posters'),
    );
    final target = File(p.join(directory.path, '$key.jpg'));
    if (await target.exists()) {
      return target;
    }

    final bytes = await _grabFrame(videoPath);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    try {
      await directory.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      Log.info('Unable to cache the poster for $videoPath: $error');
      return null;
    }
    return target;
  }

  Future<Uint8List?> _grabFrame(String videoPath) async {
    Player? player;
    try {
      player = Player(configuration: const PlayerConfiguration(muted: true));
      // media_kit opens every player with `--vid=no`; only attaching a video
      // controller turns decoding on, and without it there is no frame to
      // copy no matter how long we wait.
      final controller = VideoController(player);
      await player.setVolume(0);
      // Playing is what guarantees a decoded frame. It is silent and it is
      // stopped again as soon as the first one lands.
      await player.open(Media(videoPath));
      await controller.waitUntilFirstFrameRendered.timeout(_decodeTimeout);
      await player.pause();

      final duration = player.state.duration;
      if (duration > const Duration(seconds: 2)) {
        // Clips usually open on black, so take the frame a little way in.
        final offset = Duration(
          milliseconds: (duration.inMilliseconds ~/ 10).clamp(500, 5000),
        );
        await player.seek(offset);
        await player.stream.position
            .firstWhere(
              (value) => value >= offset - const Duration(milliseconds: 500),
            )
            .timeout(const Duration(seconds: 4), onTimeout: () => offset);
      }
      return await player.screenshot().timeout(_decodeTimeout);
    } catch (error) {
      Log.info('Unable to grab a poster frame for $videoPath: $error');
      return null;
    } finally {
      await player?.dispose();
    }
  }
}
