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
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:universal_platform/universal_platform.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

bool isYoutubeVideoUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return false;
  }

  final host = uri.host.toLowerCase();
  if (host != 'youtube.com' &&
      host != 'www.youtube.com' &&
      host != 'm.youtube.com' &&
      host != 'youtu.be') {
    return false;
  }

  return VideoId.parseVideoId(url) != null;
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

Future<InternalYoutubeVideo> downloadYoutubeVideoToInternalStorage(
  String url,
) async {
  final youtube = YoutubeExplode();
  try {
    final video = await youtube.videos.get(url);
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
      await youtube.videos.streams.get(streamInfo).pipe(output.openWrite());
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
    final video = await youtube.videos.get(url);
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
