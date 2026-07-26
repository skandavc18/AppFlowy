import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_impl.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:universal_platform/universal_platform.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

bool isYoutubeVideoUrl(String url) => youtubeVideoId(url) != null;

/// The video id [url] points at, or null when it is not a YouTube video.
String? youtubeVideoId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !_isYoutubeHost(uri.host)) {
    return null;
  }

  final id = VideoId.parseVideoId(url);
  if (id != null) {
    return id;
  }

  // Shorts links are only recognised when the id ends the URL, which the
  // `?si=...` share links do not.
  return VideoId.parseVideoId(
    Uri(scheme: uri.scheme, host: uri.host, path: uri.path).toString(),
  );
}

/// Whether [url] points at a YouTube Short, which is always portrait.
bool isYoutubeShortsUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !_isYoutubeHost(uri.host)) {
    return false;
  }
  final segments = uri.pathSegments;
  return segments.length >= 2 && segments.first == 'shorts';
}

bool _isYoutubeHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'youtube.com' ||
      normalized == 'www.youtube.com' ||
      normalized == 'm.youtube.com' ||
      normalized == 'youtu.be';
}

MuxedStreamInfo bestYoutubeMuxedStream(StreamManifest manifest) {
  final mp4Streams = manifest.muxed
      .where((stream) => stream.container == StreamContainer.mp4)
      .toList();
  final streams = mp4Streams.isNotEmpty ? mp4Streams : manifest.muxed;
  if (streams.isEmpty) {
    throw StateError('No playable video stream is available');
  }
  return streams.bestQuality;
}

typedef InternalYoutubeVideo = ({String path, String name});

/// Reports how many bytes of the video have been written so far.
///
/// [totalBytes] is null when the stream does not advertise its size.
typedef YoutubeDownloadProgress = void Function(int received, int? totalBytes);

Future<InternalYoutubeVideo> downloadYoutubeVideoToInternalStorage(
  String url, {
  YoutubeDownloadProgress? onProgress,
}) async {
  final youtube = YoutubeExplode();
  try {
    final video = await youtube.videos.get(youtubeVideoId(url) ?? url);
    final manifest = await youtube.videos.streams.getManifest(video.id);
    final streamInfo = bestYoutubeMuxedStream(manifest);
    final extension = streamInfo.container.name;
    final name =
        '${youtubeDownloadFileName(video.title, video.id.value)}.$extension';
    final applicationPath = await getIt<ApplicationDataStorage>().getPath();
    final filesDirectory = Directory(p.join(applicationPath, 'files'));
    await filesDirectory.create(recursive: true);
    final path = p.join(filesDirectory.path, '${uuid()}.$extension');
    final output = File(path);

    try {
      final totalBytes = streamInfo.size.totalBytes;
      final sink = output.openWrite();
      var received = 0;
      onProgress?.call(received, totalBytes > 0 ? totalBytes : null);
      try {
        await for (final chunk in youtube.videos.streams.get(streamInfo)) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, totalBytes > 0 ? totalBytes : null);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on Object {
      if (await output.exists()) {
        await output.delete();
      }
      rethrow;
    }

    return (path: path, name: name);
  } finally {
    youtube.close();
  }
}

Future<void> downloadYoutubeVideo(BuildContext context, String url) async {
  final youtube = YoutubeExplode();

  try {
    final video = await youtube.videos.get(youtubeVideoId(url) ?? url);
    final manifest = await youtube.videos.streams.getManifest(video.id);
    final streamInfo = bestYoutubeMuxedStream(manifest);
    final fileName =
        '${youtubeDownloadFileName(video.title, video.id.value)}.${streamInfo.container.name}';
    final stream = youtube.videos.streams.get(streamInfo);

    if (UniversalPlatform.isMobile) {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        bytes.add(chunk);
      }
      final savePath = await FilePicker().saveFile(
        fileName: fileName,
        bytes: bytes.takeBytes(),
      );
      if (savePath == null) {
        return;
      }
    } else {
      final savePath = await FilePicker().saveFile(fileName: fileName);
      if (savePath == null) {
        return;
      }
      await stream.pipe(File(savePath).openWrite());
    }

    if (context.mounted) {
      showToastNotification(
        message: LocaleKeys.grid_media_downloadSuccess.tr(),
      );
    }
  } on Exception catch (error, stackTrace) {
    Log.error('Failed to download YouTube video', error, stackTrace);
    if (context.mounted) {
      showToastNotification(
        type: ToastificationType.error,
        message: LocaleKeys
            .document_plugins_linkPreview_linkPreviewMenu_downloadFailed
            .tr(),
      );
    }
  } finally {
    youtube.close();
  }
}

String youtubeDownloadFileName(String title, String videoId) {
  final sanitized = title
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (sanitized.isEmpty) {
    return videoId;
  }
  return sanitized.length <= 150 ? sanitized : sanitized.substring(0, 150);
}

/// The state of an offline download that is running in the background.
@immutable
class YoutubeOfflineDownloadState {
  const YoutubeOfflineDownloadState({
    this.receivedBytes = 0,
    this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;

  /// Null while the total size is unknown, in which case the progress is
  /// indeterminate.
  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is YoutubeOfflineDownloadState &&
      other.receivedBytes == receivedBytes &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(receivedBytes, totalBytes);
}

/// Downloads [url] into internal storage, reporting progress along the way.
typedef YoutubeOfflineDownloader = Future<InternalYoutubeVideo> Function(
  String url, {
  YoutubeDownloadProgress? onProgress,
});

/// Runs "save for offline viewing" downloads outside of the widget tree.
///
/// Editor blocks are recycled while scrolling, so a download owned by a block
/// state would be cancelled as soon as the block leaves the viewport. Keeping
/// the downloads here also lets the embed render immediately while the file is
/// still being fetched.
class YoutubeOfflineDownloadManager {
  YoutubeOfflineDownloadManager({YoutubeOfflineDownloader? downloader})
      : _downloader = downloader ?? downloadYoutubeVideoToInternalStorage;

  static final YoutubeOfflineDownloadManager instance =
      YoutubeOfflineDownloadManager();

  final YoutubeOfflineDownloader _downloader;
  final Map<String, ValueNotifier<YoutubeOfflineDownloadState>> _downloads = {};

  /// The live progress of the download for [key], or null when nothing is
  /// being downloaded for it.
  ValueListenable<YoutubeOfflineDownloadState>? progressOf(String key) =>
      _downloads[key];

  /// Starts downloading [url] in the background, unless a download for [key]
  /// is already in flight.
  ///
  /// [onCompleted] runs once the file has been written to internal storage,
  /// [onFailed] runs when the download could not be completed.
  void start({
    required String key,
    required String url,
    required Future<void> Function(InternalYoutubeVideo video) onCompleted,
    VoidCallback? onFailed,
  }) {
    if (_downloads.containsKey(key)) {
      return;
    }

    final notifier = ValueNotifier(const YoutubeOfflineDownloadState());
    _downloads[key] = notifier;
    unawaited(_download(key, url, notifier, onCompleted, onFailed));
  }

  Future<void> _download(
    String key,
    String url,
    ValueNotifier<YoutubeOfflineDownloadState> notifier,
    Future<void> Function(InternalYoutubeVideo video) onCompleted,
    VoidCallback? onFailed,
  ) async {
    try {
      final video = await _downloader(
        url,
        onProgress: (received, totalBytes) =>
            notifier.value = YoutubeOfflineDownloadState(
          receivedBytes: received,
          totalBytes: totalBytes,
        ),
      );
      _downloads.remove(key);
      await onCompleted(video);
    } on Exception catch (error, stackTrace) {
      Log.error(
        'Failed to save YouTube video for offline viewing',
        error,
        stackTrace,
      );
      _downloads.remove(key);
      onFailed?.call();
    }
  }
}
